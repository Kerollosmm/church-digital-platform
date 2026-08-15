import { assertEquals } from "jsr:@std/assert";
import { stub } from "jsr:@std/testing/mock";
import { handleRequest } from "./index.ts";
import { FakeClient } from "../_shared/fake_supabase.ts";

function jsonRes(body: unknown): Response {
  return new Response(JSON.stringify(body), { status: 200, headers: { "Content-Type": "application/json" } });
}

Deno.test("reconcile: stale PENDING_PAYMENT found paid on Paymob -> apply_payment", async () => {
  const fake = new FakeClient(["bookings", "payments"]);
  fake.seed("payments", [{ id: 1, booking_id: 7, merchant_order_id: "17", status: "CREATED", gateway_ref: null }]);
  fake.seed("bookings", [{ id: 7, status: "PENDING_PAYMENT", locked_until: "2026-08-04T10:00:00Z", paid_amount: 50 }]);
  const applied: number[] = [];
  const fetchStub = stub(globalThis, "fetch", (url: RequestInfo | URL) => {
    if (String(url).includes("/api/ecommerce/orders/17")) {
      return Promise.resolve(jsonRes({ transactions: [{ success: true, id: 9001, amount_cents: 5000 }] }));
    }
    return Promise.resolve(jsonRes({}));
  });
  try {
    const res = await handleRequest(new Request("https://x/functions/v1/reconcile-payments", { method: "POST" }), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub, paymobApiKey: "sk", applyPayment: async (id) => { applied.push(id); },
    });
    assertEquals(res.status, 200);
    assertEquals(applied, [1]);
  } finally { fetchStub.restore(); }
});
