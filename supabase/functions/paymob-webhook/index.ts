import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { makeServiceClient } from "../_shared/client.ts";

export interface Deps {
  getClient(): unknown;
  hmacKey: string;
  applyPayment: (paymentId: number) => Promise<void>;
  applyVideoPayment: (paymentId: number) => Promise<void>;
}

// Paymob documented HMAC algorithm: HMAC-SHA-512 over the 20-field fixed transaction list
export function buildHmacPayload(t: Record<string, unknown>): string {
  const o = (t.order ?? {}) as Record<string, unknown>;
  const s = (t.source_data ?? {}) as Record<string, unknown>;
  const str = (v: unknown) => v == null ? "" : String(v);
  return [
    t.amount_cents, t.created_at, t.currency, t.error_occured, t.has_parent_transaction,
    t.id, t.integration_id, t.is_3d_secure, t.is_auth, t.is_capture,
    t.is_refunded, t.is_standalone_payment, t.is_voided, o.id, t.owner,
    t.pending, s.pan, s.sub_type, s.type, t.success,
  ].map(str).join("");
}

export async function hmacSha512Hex(secret: string, payload: string): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"]
  );
  const sig = await crypto.subtle.sign("HMAC", key, encoder.encode(payload));
  return [...new Uint8Array(sig)].map(x => x.toString(16).padStart(2, "0")).join("");
}

function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export async function handleRequest(req: Request, deps: Deps): Promise<Response> {
  const jsonHeaders = { "Content-Type": "application/json" };
  if (req.method !== "POST") return new Response("Method Not Allowed", { status: 405, headers: jsonHeaders });
  try {
    const raw = await req.text();
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    const txn = (parsed.obj ? parsed.obj : parsed) as Record<string, unknown>;
    const received = new URL(req.url).searchParams.get("hmac") ?? "";
    const expected = await hmacSha512Hex(deps.hmacKey, buildHmacPayload(txn));
    if (!safeEqual(expected, received)) return new Response(JSON.stringify({ error: "BAD_HMAC" }), { status: 401, headers: jsonHeaders });

    const orderObj = (txn.order ?? {}) as Record<string, unknown>;
    const rawOrderId = orderObj.merchant_order_id;
    const numOrderId = Number(rawOrderId);
    if (
      rawOrderId == null ||
      rawOrderId === "" ||
      rawOrderId === "undefined" ||
      rawOrderId === "null" ||
      !Number.isInteger(numOrderId) ||
      numOrderId <= 0
    ) {
      return new Response(JSON.stringify({ error: "BAD_MERCHANT_ORDER_ID" }), { status: 400, headers: jsonHeaders });
    }
    const merchantOrderId = String(rawOrderId);
    const supabase = deps.getClient() as SupabaseClient;
    const paid = Boolean(txn.success);
    const { data: existing } = await supabase.from("payments")
      .select("id, gateway_ref, status, video_id").eq("merchant_order_id", merchantOrderId).maybeSingle();
    let pay: { id: number; status: string; video_id?: number | null };
    if (existing) {
      // Idempotency: if already processed as PAID, acknowledge without re-invoking state transitions or overwriting with FAILED
      if (existing.status === "PAID") {
        return new Response(JSON.stringify({ ok: true, already_processed: true }), { status: 200, headers: jsonHeaders });
      }
      const { data: updated, error: uErr } = await supabase.from("payments")
        .update({ gateway_ref: txn.id, raw_webhook: txn, ...(paid ? {} : { status: "FAILED" }) })
        .eq("id", existing.id).select().single();
      if (uErr) throw uErr;
      pay = updated as { id: number; status: string; video_id?: number | null };
    } else {
      const { data: created, error: cErr } = await supabase.from("payments").insert({
        booking_id: null, gateway_ref: txn.id, amount: Number(txn.amount_cents) / 100,
        status: paid ? "CREATED" : "FAILED", raw_webhook: txn, merchant_order_id: merchantOrderId,
      }).select().single();
      if (cErr) throw cErr;
      pay = created as { id: number; status: string; video_id?: number | null };
    }

    if (paid) {
      if (pay.video_id) {
        await deps.applyVideoPayment(pay.id);
      } else {
        await deps.applyPayment(pay.id);
      }
    }
    return new Response(JSON.stringify({ ok: true }), { status: 200, headers: jsonHeaders });
  } catch (e) {
    console.error("paymob-webhook error", e);
    return new Response(JSON.stringify({ error: "INTERNAL" }), { status: 500, headers: jsonHeaders });
  }
}


if (import.meta.main && typeof Deno !== "undefined" && Deno.serve) {
  Deno.serve((req) => handleRequest(req, {
    getClient: () => makeServiceClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")),
    hmacKey: Deno.env.get("PAYMOB_HMAC_KEY")!,
    applyPayment: async (id) => {
      const sb = makeServiceClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
      const { error } = await sb.rpc("apply_payment", { p_payment_id: id });
      if (error) throw error;
    },
    applyVideoPayment: async (id) => {
      const sb = makeServiceClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
      const { error } = await sb.rpc("apply_video_payment", { p_payment_id: id });
      if (error) throw error;
    },
  }));
}
