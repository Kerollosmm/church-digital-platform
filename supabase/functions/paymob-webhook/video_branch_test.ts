import { assertEquals } from "jsr:@std/assert";
import { handleRequest, hmacSha512Hex } from "./index.ts";
import { hmacFields } from "../_shared/paymob.ts";
import { FakeClient } from "../_shared/fake_supabase.ts";

Deno.test("webhook routes video payment to apply_video_payment", async () => {
  const fake = new FakeClient(["payments"]);
  fake.seed("payments", [{ id: 30, booking_id: null, video_id: 5, amount: 30, status: "CREATED", gateway_ref: null, merchant_order_id: "30", raw_webhook: null }]);
  const txn = {
    id: 9100, success: true, amount_cents: 3000, created_at: "2026-08-05T10:00:00Z", currency: "EGP",
    error_occured: false, has_parent_transaction: false, integration_id: 6741, is_3d_secure: false,
    is_auth: false, is_capture: false, is_refunded: false, is_standalone_payment: false, is_voided: false,
    order: { id: 502, merchant_order_id: "30" }, owner: 1, pending: false,
    source_data: { pan: "1234", sub_type: "CARD", type: "card" },
  };
  const applied: number[] = [];
  const req = new Request(`https://x/functions/v1/paymob-webhook?hmac=${await hmacSha512Hex("s", hmacFields(txn))}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(txn),
  });
  const res = await handleRequest(req, {
    getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
    hmacKey: "s",
    applyPayment: async () => {},
    applyVideoPayment: async (id) => { applied.push(id); },
  });
  assertEquals(res.status, 200);
  assertEquals(applied, [30]);
});
