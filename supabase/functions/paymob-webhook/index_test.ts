import { assertEquals } from "jsr:@std/assert";
import { handleRequest, buildHmacPayload, hmacSha512Hex } from "./index.ts";
import { FakeClient } from "../_shared/fake_supabase.ts";

const TXN = {
  id: 9001, success: true, amount_cents: 5000, created_at: "2026-08-05T10:00:00Z", currency: "EGP",
  error_occured: false, has_parent_transaction: false, integration_id: 6741, is_3d_secure: false,
  is_auth: false, is_capture: false, is_refunded: false, is_standalone_payment: false, is_voided: false,
  order: { id: 501, merchant_order_id: "17" }, owner: 1, pending: false,
  source_data: { pan: "1234", sub_type: "CARD", type: "card" },
};

Deno.test("paymob-webhook: valid HMAC + success -> upsert payment, raw_webhook stored, apply_payment called", async () => {
  const fake = new FakeClient(["payments"]);
  fake.seed("payments", [{ id: 17, booking_id: 7, amount: 50, status: "CREATED", gateway_ref: null, merchant_order_id: "17", raw_webhook: null }]);
  const hmacPayload = buildHmacPayload(TXN);
  const secret = "hmac_secret_123";
  const signature = await hmacSha512Hex(secret, hmacPayload);
  let appliedId: number | null = null;
  const req = new Request(`https://x/functions/v1/paymob-webhook?hmac=${signature}`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify(TXN),
  });
  const res = await handleRequest(req, {
    getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
    hmacKey: secret,
    applyPayment: async (id) => { appliedId = id; },
    applyVideoPayment: async () => {},
  });
  assertEquals(res.status, 200);
  assertEquals(appliedId, 17);
  const pay = fake.tableRows("payments")[0];
  assertEquals(pay.gateway_ref, 9001);
  assertEquals(pay.raw_webhook, TXN);
});

Deno.test("paymob-webhook: invalid HMAC rejected 401", async () => {
  const fake = new FakeClient(["payments"]);
  const req = new Request("https://x/functions/v1/paymob-webhook?hmac=deadbeef", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify(TXN),
  });
  const res = await handleRequest(req, {
    getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
    hmacKey: "other", applyPayment: async () => {}, applyVideoPayment: async () => {},
  });
  assertEquals(res.status, 401);
});
