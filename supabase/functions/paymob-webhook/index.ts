import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { makeServiceClient } from "../_shared/client.ts";
import { respond } from "../_shared/http.ts";
import { hmacFields } from "../_shared/paymob.ts";
import { recordWebhookPayment } from "../_shared/payments-gateway.ts";

export interface Deps {
  getClient(): unknown;
  hmacKey: string;
  applyPayment: (paymentId: number) => Promise<void>;
}

export async function hmacSha512Hex(
  secret: string,
  payload: string,
): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, encoder.encode(payload));
  return [...new Uint8Array(sig)]
    .map((x) => x.toString(16).padStart(2, "0"))
    .join("");
}

function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export async function handleRequest(
  req: Request,
  deps: Deps,
): Promise<Response> {
  if (req.method !== "POST") {
    return respond(400, "BAD_REQUEST", "Method Not Allowed");
  }
  try {
    const raw = await req.text();
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    const txn = (parsed.obj ? parsed.obj : parsed) as Record<string, unknown>;
    const received = (
      new URL(req.url).searchParams.get("hmac") ?? ""
    )
      .toLowerCase()
      .trim();
    const expected = (
      await hmacSha512Hex(deps.hmacKey, hmacFields(txn))
    )
      .toLowerCase()
      .trim();
    if (!safeEqual(expected, received)) {
      return respond(401, "UNAUTHORIZED", "BAD_HMAC");
    }

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
      return respond(400, "BAD_REQUEST", "BAD_MERCHANT_ORDER_ID");
    }
    const merchantOrderId = String(rawOrderId);
    const supabase = deps.getClient() as SupabaseClient;
    const paid = Boolean(txn.success);
    const { data: existing } = await supabase
      .from("payments")
      .select("id, gateway_ref, status")
      .eq("merchant_order_id", merchantOrderId)
      .maybeSingle();
    if (existing && (existing as { status: string }).status === "PAID") {
      // Idempotency: already processed as PAID — acknowledge without re-invoking
      return respond(200, { ok: true, already_processed: true });
    }

    const recorded = await recordWebhookPayment(supabase, {
      merchantOrderId,
      gatewayRef: String(txn.id ?? ""),
      amount: Math.round(Number(txn.amount_cents ?? 0) / 100),
      paid,
      raw: txn,
    });
    if (!recorded.ok) throw new Error(recorded.errorCode ?? "INTERNAL");
    const pay = recorded.data as { id: number; already_paid: boolean };

    if (paid) {
      await deps.applyPayment(pay.id);
    }
    return respond(200, { ok: true });
  } catch (e) {
    console.error("paymob-webhook error", e);
    return respond(500, "INTERNAL");
  }
}

if (import.meta.main && typeof Deno !== "undefined" && Deno.serve) {
  const hmacKey = Deno.env.get("PAYMOB_HMAC_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!hmacKey || !supabaseUrl || !serviceKey) {
    throw new Error(
      "Missing required environment variables: PAYMOB_HMAC_KEY, SUPABASE_URL, or SUPABASE_SERVICE_ROLE_KEY.",
    );
  }
  Deno.serve((req) =>
    handleRequest(req, {
      getClient: () => makeServiceClient(supabaseUrl, serviceKey),
      hmacKey,
      applyPayment: async (id) => {
        const sb = makeServiceClient(supabaseUrl, serviceKey);
        const { error } = await sb.rpc("apply_payment", { p_payment_id: id });
        if (error) throw error;
      },
    }),
  );
}
