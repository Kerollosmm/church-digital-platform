import type { SupabaseClient, User } from "npm:@supabase/supabase-js@2";
import { createClient } from "npm:@supabase/supabase-js@2";
import { makeServiceClient } from "../_shared/client.ts";

export interface Deps {
  getClient(): unknown;
  fetch: typeof fetch;
  paymobApiKey: string;
  integrationId: number;
  iframeId: number;
  amountMultiplier: number;
  getUser?: (token: string) => Promise<{ data: { user: User | null }; error: unknown }>;
}

export async function handleRequest(req: Request, deps: Deps): Promise<Response> {
  const cors = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Content-Type": "application/json",
  };
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const authHeader = req.headers.get("Authorization");
    let callerUser: User | null = null;
    if (authHeader && deps.getUser) {
      const token = authHeader.replace(/^Bearer\s+/i, "");
      const { data, error: authErr } = await deps.getUser(token);
      if (authErr || !data?.user) {
        return new Response(JSON.stringify({ error: "UNAUTHORIZED" }), { status: 401, headers: cors });
      }
      callerUser = data.user;
    }

    const body = await req.json() as Record<string, unknown>;
    const paymentId = Number(body.payment_id ?? 0);
    const bookingId = Number(body.booking_id ?? 0);
    const supabase = deps.getClient() as SupabaseClient;
    let orderId: number;
    let amountCents: number;
    let createdPaymentId: number | null = null;

    if (paymentId > 0) {
      const { data: pay, error: pErr } = await supabase.from("payments")
        .select("id, amount, booking_id, video_id").eq("id", paymentId).single();
      if (pErr || !pay) return new Response(JSON.stringify({ error: "PAYMENT_NOT_FOUND" }), { status: 404, headers: cors });

      if (callerUser) {
        if (pay.booking_id) {
          const { data: b } = await supabase.from("bookings").select("user_id").eq("id", pay.booking_id).maybeSingle();
          if (b && b.user_id && b.user_id !== callerUser.id) {
            return new Response(JSON.stringify({ error: "FORBIDDEN" }), { status: 403, headers: cors });
          }
        }
      }

      orderId = pay.id as number;
      amountCents = Math.round((pay.amount as number) * deps.amountMultiplier);
    } else if (bookingId > 0) {
      if (!Number.isInteger(bookingId)) return new Response(JSON.stringify({ error: "BAD_REQUEST" }), { status: 400, headers: cors });
      const { data: b, error: bErr } = await supabase.from("bookings").select("id, user_id, paid_amount, slot_id").eq("id", bookingId).single();
      if (bErr || !b) return new Response(JSON.stringify({ error: "BOOKING_NOT_FOUND" }), { status: 404, headers: cors });

      if (callerUser && b.user_id && b.user_id !== callerUser.id) {
        return new Response(JSON.stringify({ error: "FORBIDDEN" }), { status: 403, headers: cors });
      }

      let amount = (b.paid_amount as number) || 0;
      if (amount === 0 && b.slot_id) {
        const { data: slot } = await supabase.from("service_slots").select("price").eq("id", b.slot_id).single();
        if (slot?.price) amount = slot.price;
      }
      amountCents = Math.round(amount * deps.amountMultiplier);
      const { data: pay, error: pErr } = await supabase.from("payments").insert({
        booking_id: bookingId, amount, status: "CREATED", gateway_ref: null,
      }).select().single();
      if (pErr) throw pErr;
      orderId = pay.id as number;
      createdPaymentId = orderId;
    } else {
      return new Response(JSON.stringify({ error: "BAD_REQUEST" }), { status: 400, headers: cors });
    }
    await supabase.from("payments").update({ merchant_order_id: String(orderId) }).eq("id", orderId);

    // STEP 1: Auth token
    const authRes = await deps.fetch("https://accept.paymob.com/api/auth/tokens", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ api_key: deps.paymobApiKey }),
    });
    if (!authRes.ok) {
      if (createdPaymentId) await supabase.from("payments").update({ status: "FAILED" }).eq("id", createdPaymentId);
      return new Response(JSON.stringify({ error: "PAYMOB_UPSTREAM_ERROR" }), { status: 502, headers: cors });
    }
    const authJson = (await authRes.json()) as Record<string, unknown>;
    const token = String(authJson.token ?? "");
    if (!token) {
      if (createdPaymentId) await supabase.from("payments").update({ status: "FAILED" }).eq("id", createdPaymentId);
      return new Response(JSON.stringify({ error: "PAYMOB_UPSTREAM_ERROR" }), { status: 502, headers: cors });
    }

    // STEP 2: Order registration
    const orderRes = await deps.fetch("https://accept.paymob.com/api/ecommerce/orders", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        auth_token: token, delivery_needed: "false",
        amount_cents: String(amountCents), currency: "EGP",
        merchant_order_id: String(orderId), items: [],
      }),
    });
    if (!orderRes.ok) {
      if (createdPaymentId) await supabase.from("payments").update({ status: "FAILED" }).eq("id", createdPaymentId);
      return new Response(JSON.stringify({ error: "PAYMOB_UPSTREAM_ERROR" }), { status: 502, headers: cors });
    }
    const orderJson = (await orderRes.json()) as Record<string, unknown>;
    const paymobOrderId = Number(orderJson.id ?? 0);
    if (!paymobOrderId) {
      if (createdPaymentId) await supabase.from("payments").update({ status: "FAILED" }).eq("id", createdPaymentId);
      return new Response(JSON.stringify({ error: "PAYMOB_UPSTREAM_ERROR" }), { status: 502, headers: cors });
    }

    // STEP 3: Payment key
    const keyRes = await deps.fetch("https://accept.paymob.com/api/acceptance/payment_keys", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        auth_token: token, amount_cents: String(amountCents),
        expiration: 3600, order_id: String(paymobOrderId),
        billing_data: { first_name: "Parishioner", last_name: "User", email: "p@example.com", phone_number: "+201000000000", country: "EG", city: "Cairo", street: "N/A", building: "N/A", floor: "N/A", apartment: "N/A" },
        currency: "EGP", integration_id: deps.integrationId,
      }),
    });
    if (!keyRes.ok) {
      if (createdPaymentId) await supabase.from("payments").update({ status: "FAILED" }).eq("id", createdPaymentId);
      return new Response(JSON.stringify({ error: "PAYMOB_UPSTREAM_ERROR" }), { status: 502, headers: cors });
    }
    const keyJson = (await keyRes.json()) as Record<string, unknown>;
    const paymentKey = String(keyJson.token ?? "");
    if (!paymentKey) {
      if (createdPaymentId) await supabase.from("payments").update({ status: "FAILED" }).eq("id", createdPaymentId);
      return new Response(JSON.stringify({ error: "PAYMOB_UPSTREAM_ERROR" }), { status: 502, headers: cors });
    }

    const url = `https://accept.paymob.com/api/acceptance/iframes/${deps.iframeId}?payment_token=${paymentKey}`;
    return new Response(JSON.stringify({ checkout_url: url, payment_id: orderId }), { status: 200, headers: cors });
  } catch (e) {
    console.error("paymob-checkout error", e);
    return new Response(JSON.stringify({ error: "INTERNAL" }), { status: 500, headers: cors });
  }
}

if (import.meta.main && typeof Deno !== "undefined" && Deno.serve) {
  Deno.serve((req) => handleRequest(req, {
    getClient: () => makeServiceClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")),
    getUser: async (token: string) => {
      const client = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_ANON_KEY")!,
      );
      return await client.auth.getUser(token);
    },
    fetch,
    paymobApiKey: Deno.env.get("PAYMOB_API_KEY")!,
    integrationId: Number(Deno.env.get("PAYMOB_INTEGRATION_ID") ?? "0"),
    iframeId: Number(Deno.env.get("PAYMOB_IFRAME_ID") ?? "0"),
    amountMultiplier: 100,
  }));
}

