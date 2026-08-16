import { assertEquals } from "jsr:@std/assert";
import { createPaymob, hmacFields } from "../_shared/paymob.ts";

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.test("paymob adapter: session caches auth token until expiry - 60s", async () => {
  let callCount = 0;
  const fakeFetch = (url: RequestInfo | URL) => {
    if (String(url).endsWith("/api/auth/tokens")) {
      callCount++;
      return Promise.resolve(jsonResponse({ token: "tok_123", expires_in: 3600 }));
    }
    return Promise.resolve(jsonResponse({}));
  };

  const client = createPaymob({ apiKey: "test_key", fetch: fakeFetch as typeof fetch });
  const res1 = await client.session();
  const res2 = await client.session();

  assertEquals(res1.ok, true);
  assertEquals(res2.ok, true);
  if (res1.ok && res2.ok) {
    assertEquals(res1.token, "tok_123");
    assertEquals(res2.token, "tok_123");
  }
  assertEquals(callCount, 1); // Caching prevents 2nd call
});

Deno.test("paymob adapter: checkout executes 3-step handshake and returns iframe URL", async () => {
  const seenUrls: string[] = [];
  const fakeFetch = (url: RequestInfo | URL, init?: RequestInit) => {
    seenUrls.push(String(url));
    if (String(url).endsWith("/api/auth/tokens")) {
      return Promise.resolve(jsonResponse({ token: "tok_auth" }));
    }
    if (String(url).endsWith("/api/ecommerce/orders")) {
      const body = JSON.parse(String(init?.body));
      assertEquals(body.amount_cents, "5000");
      assertEquals(body.merchant_order_id, "ord_999");
      return Promise.resolve(jsonResponse({ id: 101 }));
    }
    if (String(url).endsWith("/api/acceptance/payment_keys")) {
      const body = JSON.parse(String(init?.body));
      assertEquals(body.order_id, "101");
      return Promise.resolve(jsonResponse({ token: "pkey_777" }));
    }
    return Promise.resolve(jsonResponse({}));
  };

  const client = createPaymob({ apiKey: "test_key", fetch: fakeFetch as typeof fetch });
  const result = await client.checkout({
    amountCents: 5000,
    merchantOrderId: "ord_999",
    integrationId: 12,
    iframeId: 34,
  });

  assertEquals(result.ok, true);
  if (result.ok) {
    assertEquals(result.paymobOrderId, 101);
    assertEquals(result.paymentKey, "pkey_777");
    assertEquals(
      result.checkoutUrl,
      "https://accept.paymob.com/api/acceptance/iframes/34?payment_token=pkey_777",
    );
  }
});

Deno.test("paymob adapter: refund calls void_refund endpoint", async () => {
  let refundCalled = false;
  const fakeFetch = (url: RequestInfo | URL, init?: RequestInit) => {
    if (String(url).endsWith("/api/auth/tokens")) {
      return Promise.resolve(jsonResponse({ token: "tok_auth" }));
    }
    if (String(url).endsWith("/api/acceptance/void_refund/refund")) {
      refundCalled = true;
      const body = JSON.parse(String(init?.body));
      assertEquals(body.transaction_id, "txn_555");
      assertEquals(body.amount_cents, 2500);
      return Promise.resolve(jsonResponse({ success: true, id: 999 }));
    }
    return Promise.resolve(jsonResponse({}));
  };

  const client = createPaymob({ apiKey: "test_key", fetch: fakeFetch as typeof fetch });
  const res = await client.refund({ transactionId: "txn_555", amountCents: 2500 });
  assertEquals(refundCalled, true);
  assertEquals(res.ok, true);
});

Deno.test("paymob adapter: orderStatus fetches order and transactions", async () => {
  const fakeFetch = (url: RequestInfo | URL) => {
    if (String(url).endsWith("/api/auth/tokens")) {
      return Promise.resolve(jsonResponse({ token: "tok_auth" }));
    }
    if (String(url).endsWith("/api/ecommerce/orders/ord_123")) {
      return Promise.resolve(jsonResponse({
        id: 123,
        transactions: [{ id: 1, success: true, amount_cents: 5000 }],
      }));
    }
    return Promise.resolve(jsonResponse({}, 404));
  };

  const client = createPaymob({ apiKey: "test_key", fetch: fakeFetch as typeof fetch });
  const status = await client.orderStatus("ord_123");
  assertEquals(status.ok, true);
  if (status.ok) {
    assertEquals(status.id, 123);
    assertEquals(status.transactions.length, 1);
    assertEquals(status.transactions[0].success, true);
  }
});

Deno.test("paymob adapter: non-2xx returns typed UPSTREAM_ERROR with status", async () => {
  const fakeFetch = () => Promise.resolve(new Response("Service Unavailable", { status: 503 }));
  const client = createPaymob({ apiKey: "test_key", fetch: fakeFetch as typeof fetch });

  const res = await client.session();
  assertEquals(res.ok, false);
  if (!res.ok) {
    assertEquals(res.kind, "UPSTREAM_ERROR");
    assertEquals(res.status, 503);
  }
});

Deno.test("paymob adapter: 2xx with invalid JSON returns typed UPSTREAM_ERROR", async () => {
  const fakeFetch = () => Promise.resolve(new Response("<html>Bad Gateway</html>", { status: 200 }));
  const client = createPaymob({ apiKey: "test_key", fetch: fakeFetch as typeof fetch });

  const res = await client.session();
  assertEquals(res.ok, false);
  if (!res.ok) {
    assertEquals(res.kind, "UPSTREAM_ERROR");
  }
});

Deno.test("paymob adapter: hmacFields() returns string[] of 20 field names per contract", () => {
  const fields = hmacFields();
  assertEquals(Array.isArray(fields), true);
  assertEquals(fields.length, 20);
  assertEquals(fields[0], "amount_cents");
  assertEquals(fields[fields.length - 1], "success");
});

Deno.test("paymob adapter: hmacFields(txn) correctly concatenates 20 fields", () => {
  const txn = {
    amount_cents: 5000,
    created_at: "2026-08-16T12:00:00.000Z",
    currency: "EGP",
    error_occured: false,
    has_parent_transaction: false,
    id: 12345,
    integration_id: 678,
    is_3d_secure: true,
    is_auth: false,
    is_capture: false,
    is_refunded: false,
    is_standalone_payment: false,
    is_voided: false,
    order: { id: 999 },
    owner: 42,
    pending: false,
    source_data: { pan: "2345", sub_type: "MasterCard", type: "card" },
    success: true,
  };

  const fields = hmacFields(txn);
  const expected = "50002026-08-16T12:00:00.000ZEGPfalsefalse12345678truefalsefalsefalsefalsefalse99942false2345MasterCardcardtrue";
  assertEquals(fields, expected);
});
