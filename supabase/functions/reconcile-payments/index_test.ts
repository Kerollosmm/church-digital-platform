import { assertEquals } from "jsr:@std/assert";
import { stub } from "jsr:@std/testing/mock";
import { handleRequest } from "./index.ts";
import { FakeClient } from "../_shared/fake_supabase.ts";

function jsonRes(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.test("reconcile: stale PENDING_PAYMENT found paid on Paymob -> apply_payment", async () => {
  const fake = new FakeClient(["bookings", "payments"]);
  fake.seed("payments", [
    { id: 1, booking_id: 7, merchant_order_id: "17", status: "CREATED", gateway_ref: null },
  ]);
  fake.seed("bookings", [
    { id: 7, status: "PENDING_PAYMENT", locked_until: "2026-08-04T10:00:00Z", paid_amount: 50 },
  ]);
  const applied: number[] = [];
  const fetchStub = stub(globalThis, "fetch", (url: RequestInfo | URL) => {
    if (String(url).endsWith("/api/auth/tokens")) {
      return Promise.resolve(jsonRes({ token: "tok_auth" }));
    }
    if (String(url).includes("/api/ecommerce/orders/17")) {
      return Promise.resolve(
        jsonRes({
          id: 17,
          transactions: [{ success: true, id: 9001, amount_cents: 5000 }],
        }),
      );
    }
    return Promise.resolve(jsonRes({}));
  });
  try {
    const res = await handleRequest(
      new Request("https://x/functions/v1/reconcile-payments", { method: "POST" }),
      {
        getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
        fetch: fetchStub,
        paymobApiKey: "sk",
        applyPayment: async (id) => {
          applied.push(id);
        },
      },
    );
    assertEquals(res.status, 200);
    assertEquals(applied, [1]);
  } finally {
    fetchStub.restore();
  }
});

Deno.test("reconcile: stale PENDING_PAYMENT unpaid on Paymob -> cancels booking and marks payment FAILED", async () => {
  const fake = new FakeClient(["bookings", "payments"]);
  fake.seed("payments", [
    { id: 2, booking_id: 8, merchant_order_id: "18", status: "CREATED", gateway_ref: null },
  ]);
  fake.seed("bookings", [
    { id: 8, status: "PENDING_PAYMENT", locked_until: "2026-08-04T10:00:00Z", paid_amount: 50 },
  ]);
  const applied: number[] = [];
  const fetchStub = stub(globalThis, "fetch", (url: RequestInfo | URL) => {
    if (String(url).endsWith("/api/auth/tokens")) {
      return Promise.resolve(jsonRes({ token: "tok_auth" }));
    }
    if (String(url).includes("/api/ecommerce/orders/18")) {
      return Promise.resolve(
        jsonRes({
          id: 18,
          transactions: [{ success: false, id: 9002, amount_cents: 5000 }],
        }),
      );
    }
    return Promise.resolve(jsonRes({}));
  });
  try {
    const res = await handleRequest(
      new Request("https://x/functions/v1/reconcile-payments", { method: "POST" }),
      {
        getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
        fetch: fetchStub,
        paymobApiKey: "sk",
        applyPayment: async (id) => {
          applied.push(id);
        },
      },
    );
    assertEquals(res.status, 200);
    assertEquals(applied.length, 0);
    assertEquals(fake.tableRows("payments")[0].status, "FAILED");
  } finally {
    fetchStub.restore();
  }
});

Deno.test("reconcile: upstream error marks payment FAILED with incident logging", async () => {
  const fake = new FakeClient(["bookings", "payments"]);
  fake.seed("payments", [
    { id: 3, booking_id: 9, merchant_order_id: "19", status: "CREATED", gateway_ref: null },
  ]);
  fake.seed("bookings", [
    { id: 9, status: "PENDING_PAYMENT", locked_until: "2026-08-04T10:00:00Z", paid_amount: 50 },
  ]);
  const fetchStub = stub(globalThis, "fetch", (url: RequestInfo | URL) => {
    if (String(url).endsWith("/api/auth/tokens")) {
      return Promise.resolve(jsonRes({ token: "tok_auth" }));
    }
    return Promise.resolve(new Response("Malformed", { status: 502, headers: { "Content-Type": "text/html" } }));
  });
  try {
    const res = await handleRequest(
      new Request("https://x/functions/v1/reconcile-payments", { method: "POST" }),
      {
        getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
        fetch: fetchStub,
        paymobApiKey: "sk",
        applyPayment: async () => {},
      },
    );
    assertEquals(res.status, 200);
    const body = await res.json();
    assertEquals(body.ok, true);
    assertEquals(body.resolved, 1);
    assertEquals(fake.tableRows("payments")[0].status, "FAILED");
  } finally {
    fetchStub.restore();
  }
});

