// Run against staging with: node supabase/e2e/book_pay_flow.mjs
// Requires env: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY, PAYMOB_HMAC_KEY (staging sandbox), TEST_USER_ID, TEST_USER_PHONE, TEST_SLOT_ID
import { createClient } from "@supabase/supabase-js";
import { hmacFields } from "../functions/_shared/paymob.ts";

const url = process.env.SUPABASE_URL;
const service = createClient(url, process.env.SUPABASE_SERVICE_ROLE_KEY);

const assert = (cond, msg) => { if (!cond) { console.error("FAIL:", msg); process.exit(1); } };
const hmac = async (secret, payload) => {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-512" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload));
  return [...new Uint8Array(sig)].map(x => x.toString(16).padStart(2, "0")).join("");
};

// 1. book
const { data: user } = await service.from("public.users").select("id, phone").eq("id", process.env.TEST_USER_ID).single();
const { data: booking, error: bookErr } = await service.rpc("book_slot", { p_slot_id: Number(process.env.TEST_SLOT_ID), p_opt_in: true });
assert(!bookErr && booking, "book_slot failed");
assert(booking.status === "PENDING_PAYMENT", "booking not PENDING_PAYMENT");

// 2. checkout intent
const checkoutRes = await fetch(`${url}/functions/v1/paymob-checkout`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Authorization: `Bearer ${process.env.SUPABASE_ANON_KEY}` },
  body: JSON.stringify({ booking_id: booking.id }),
});
assert(checkoutRes.ok, "paymob-checkout failed");
const checkout = await checkoutRes.json();
assert(checkout.checkout_url.includes("accept.paymob.com"), "no checkout url");

// 3. simulate Paymob sandbox webhook (same code path as prod)
const pay = (await service.from("payments").select("id").eq("merchant_order_id", String(checkout.payment_id)).single()).data;
const txn = {
  id: 99001, success: true, amount_cents: 5000, created_at: new Date().toISOString(), currency: "EGP",
  error_occured: false, has_parent_transaction: false, integration_id: 6741, is_3d_secure: false,
  is_auth: false, is_capture: false, is_refunded: false, is_standalone_payment: false, is_voided: false,
  order: { id: 501, merchant_order_id: String(pay.id) }, owner: 1, pending: false,
  source_data: { pan: "1234", sub_type: "CARD", type: "card" },
};
const signature = await hmac(process.env.PAYMOB_HMAC_KEY, hmacFields(txn));
const hookRes = await fetch(`${url}/functions/v1/paymob-webhook?hmac=${signature}`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify(txn),
});
assert(hookRes.ok, `webhook rejected: ${hookRes.status}`);
const after = (await service.from("bookings").select("status").eq("id", booking.id).single()).data;
assert(after.status === "AWAITING_CALL", `expected AWAITING_CALL, got ${after.status}`);

// 4. confirm
const { error: confirmErr } = await service.rpc("confirm_booking", { p_booking_id: booking.id });
assert(!confirmErr, "confirm_booking failed");
const confirmed = (await service.from("bookings").select("status").eq("id", booking.id).single()).data;
assert(confirmed.status === "CONFIRMED", "not CONFIRMED");

// 5. WhatsApp outbox asserts
const { data: outbox } = await service.from("event_outbox")
  .select("handler_type, payload, status").eq("payload->>phone", user.phone).order("created_at", { ascending: true });
const names = outbox.map((r) => r.payload.template_name);
assert(names.includes("booking_payment_received"), "booking_payment_received missing");
assert(names.includes("booking_confirmed"), "booking_confirmed missing");
assert(outbox.every((r) => r.handler_type === "WHATSAPP" && r.status === "PENDING"), "events PENDING until dispatcher runs");

console.log("E2E PASS: book -> pay -> confirm -> outbox");
