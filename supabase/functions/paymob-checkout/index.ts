import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { makeServiceClient } from "../_shared/client.ts";

export interface Deps {
  getClient(): unknown;
  fetch: typeof fetch;
  paymobApiKey: string;
  integrationId: number;
  iframeId: number;
  amountMultiplier: number;
}

export async function handleRequest(req: Request, deps: Deps): Promise<Response> {
  const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "content-type" };
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const body = await req.json() as Record<string, unknown>;
    const paymentId = Number(body.payment_id ?? 0);
    const bookingId = Number(body.booking_id ?? 0);
    const supabase = deps.getClient() as SupabaseClient;
    let orderId: number;
    let amountCents: number;
    if (paymentId > 0) {
      const { data: pay, error: pErr } = await supabase.from("payments")
        .select("id, amount").eq("id", paymentId).single();
      if (pErr || !pay) return new Response(JSON.stringify({ error: "PAYMENT_NOT_FOUND" }), { status: 404, headers: cors });
      orderId = pay.id as number;
      amountCents = Math.round((pay.amount as number) * deps.amountMultiplier);
    } else if (bookingId > 0) {
      if (!Number.isInteger(bookingId)) return new Response(JSON.stringify({ error: "BAD_REQUEST" }), { status: 400, headers: cors });
      const { data: b, error: bErr } = await supabase.from("bookings").select("id, paid_amount, slot_id").eq("id", bookingId).single();
      if (bErr || !b) return new Response(JSON.stringify({ error: "BOOKING_NOT_FOUND" }), { status: 404, headers: cors });
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
    } else {
      return new Response(JSON.stringify({ error: "BAD_REQUEST" }), { status: 400, headers: cors });
    }
    await supabase.from("payments").update({ merchant_order_id: String(orderId) }).eq("id", orderId);

    // STEP 1: Auth token
    const authRes = await deps.fetch("https://accept.paymob.com/api/auth/tokens", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ api_key: deps.paymobApiKey }),
    });
    const authJson = (await authRes.json()) as Record<string, unknown>;
    const token = String(authJson.token ?? "");

    // STEP 2: Order registration
    const orderRes = await deps.fetch("https://accept.paymob.com/api/ecommerce/orders", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        auth_token: token, delivery_needed: "false",
        amount_cents: String(amountCents), currency: "EGP",
        merchant_order_id: String(orderId), items: [],
      }),
    });
    const orderJson = (await orderRes.json()) as Record<string, unknown>;
    const paymobOrderId = Number(orderJson.id ?? 0);

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
    const keyJson = (await keyRes.json()) as Record<string, unknown>;
    const paymentKey = String(keyJson.token ?? "");

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
    fetch,
    paymobApiKey: Deno.env.get("PAYMOB_API_KEY")!,
    integrationId: Number(Deno.env.get("PAYMOB_INTEGRATION_ID") ?? "0"),
    iframeId: Number(Deno.env.get("PAYMOB_IFRAME_ID") ?? "0"),
    amountMultiplier: 100,
  }));
}
