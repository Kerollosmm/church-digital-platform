import { assertEquals } from "jsr:@std/assert";
import { stub } from "jsr:@std/testing/mock";
import { handleRequest } from "./index.ts";
import { FakeClient } from "../_shared/fake_supabase.ts";

function jsonRes(body: unknown): Response {
  return new Response(JSON.stringify(body), { status: 200, headers: { "Content-Type": "application/json" } });
}

Deno.test("paymob-checkout: booking_id creates CREATED payment and returns iframe URL", async () => {
  const fake = new FakeClient(["bookings", "payments"]);
  fake.seed("bookings", [{ id: 7, paid_amount: 50, status: "PENDING_PAYMENT" }]);
  const seenUrls: string[] = [];
  const fetchStub = stub(globalThis, "fetch", (url: RequestInfo | URL) => {
    seenUrls.push(String(url));
    if (String(url).endsWith("/api/auth/tokens")) return Promise.resolve(jsonRes({ token: "t1" }));
    if (String(url).endsWith("/api/ecommerce/orders")) return Promise.resolve(jsonRes({ id: 99 }));
    if (String(url).endsWith("/api/acceptance/payment_keys")) return Promise.resolve(jsonRes({ token: "pkey1" }));
    return Promise.resolve(jsonRes({}));
  });
  try {
    const res = await handleRequest(new Request("https://x/functions/v1/paymob-checkout", {
      method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ booking_id: 7 }),
    }), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub, paymobApiKey: "sk", integrationId: 1, iframeId: 2, amountMultiplier: 100,
    });
    assertEquals(res.status, 200);
    const body = await res.json() as Record<string, unknown>;
    assertEquals(body.checkout_url, "https://accept.paymob.com/api/acceptance/iframes/2?payment_token=pkey1");
    assertEquals(fake.tableRows("payments").length, 1);
  } finally { fetchStub.restore(); }
});

Deno.test("paymob-checkout: payment_id uses existing CREATED payment and returns iframe URL", async () => {
  const fake = new FakeClient(["payments"]);
  fake.seed("payments", [{ id: 30, video_id: 5, amount: 30, status: "CREATED" }]);
  const fetchStub = stub(globalThis, "fetch", (url: RequestInfo | URL) => {
    if (String(url).endsWith("/api/auth/tokens")) return Promise.resolve(jsonRes({ token: "t1" }));
    if (String(url).endsWith("/api/ecommerce/orders")) return Promise.resolve(jsonRes({ id: 99 }));
    if (String(url).endsWith("/api/acceptance/payment_keys")) return Promise.resolve(jsonRes({ token: "pkey1" }));
    return Promise.resolve(jsonRes({}));
  });
  try {
    const res = await handleRequest(new Request("https://x/functions/v1/paymob-checkout", {
      method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ payment_id: 30 }),
    }), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub, paymobApiKey: "sk", integrationId: 1, iframeId: 2, amountMultiplier: 100,
    });
    assertEquals(res.status, 200);
    const body = await res.json() as Record<string, unknown>;
    assertEquals(body.checkout_url, "https://accept.paymob.com/api/acceptance/iframes/2?payment_token=pkey1");
    assertEquals(fake.tableRows("payments").length, 1);
  } finally { fetchStub.restore(); }
});
