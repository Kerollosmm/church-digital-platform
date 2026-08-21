import { assertEquals } from "jsr:@std/assert";
import { handleRequest, hmacSha512Hex } from "./index.ts";
import { hmacFields } from "../_shared/paymob.ts";
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
  const hmacPayload = hmacFields(TXN);
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
  });
  assertEquals(res.status, 200);
  assertEquals(appliedId, 17);
  const pay = fake.tableRows("payments")[0];
  assertEquals(pay.gateway_ref, "9001");
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
    hmacKey: "other", applyPayment: async () => {},
  });
  assertEquals(res.status, 401);
});

Deno.test("paymob-webhook: missing or undefined merchant_order_id returns 400", async () => {
  const fake = new FakeClient(["payments"]);
  const badTxn = { ...TXN, order: { id: 501, merchant_order_id: "undefined" } };
  const hmacPayload = hmacFields(badTxn);
  const secret = "hmac_secret_123";
  const signature = await hmacSha512Hex(secret, hmacPayload);
  const req = new Request(`https://x/functions/v1/paymob-webhook?hmac=${signature}`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify(badTxn),
  });
  const res = await handleRequest(req, {
    getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
    hmacKey: secret, applyPayment: async () => {},
  });
  assertEquals(res.status, 400);
});

Deno.test("paymob-webhook: already PAID payment is acknowledged without re-applying", async () => {
  const fake = new FakeClient(["payments"]);
  fake.seed("payments", [{ id: 17, status: "PAID", merchant_order_id: "17" }]);
  const hmacPayload = hmacFields(TXN);
  const secret = "hmac_secret_123";
  const signature = await hmacSha512Hex(secret, hmacPayload);
  let appliedCalls = 0;
  const req = new Request(`https://x/functions/v1/paymob-webhook?hmac=${signature}`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify(TXN),
  });
  const res = await handleRequest(req, {
    getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
    hmacKey: secret,
    applyPayment: async () => { appliedCalls++; },
  });
  assertEquals(res.status, 200);
  assertEquals(appliedCalls, 0);
});

Deno.test("paymob-webhook: non-positive or non-numeric merchant_order_id returns 400", async () => {
  const fake = new FakeClient(["payments"]);
  for (const badId of ["0", "-5", "abc", "12.34"]) {
    const badTxn = { ...TXN, order: { id: 501, merchant_order_id: badId } };
    const hmacPayload = hmacFields(badTxn);
    const secret = "hmac_secret_123";
    const signature = await hmacSha512Hex(secret, hmacPayload);
    const req = new Request(`https://x/functions/v1/paymob-webhook?hmac=${signature}`, {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify(badTxn),
    });
    const res = await handleRequest(req, {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      hmacKey: secret, applyPayment: async () => {},
    });
    assertEquals(res.status, 400);
  }
});

Deno.test("paymob-webhook: failure webhook on already PAID payment returns already_processed without modifying status to FAILED", async () => {
  const fake = new FakeClient(["payments"]);
  fake.seed("payments", [{ id: 17, status: "PAID", merchant_order_id: "17" }]);
  const failedTxn = { ...TXN, success: false };
  const hmacPayload = hmacFields(failedTxn);
  const secret = "hmac_secret_123";
  const signature = await hmacSha512Hex(secret, hmacPayload);
  const req = new Request(`https://x/functions/v1/paymob-webhook?hmac=${signature}`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify(failedTxn),
  });
  const res = await handleRequest(req, {
    getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
    hmacKey: secret,
    applyPayment: async () => {},
  });
  assertEquals(res.status, 200);
  const body = await res.json() as Record<string, unknown>;
  assertEquals(body.already_processed, true);
  const pay = fake.tableRows("payments")[0];
  assertEquals(pay.status, "PAID");
});


