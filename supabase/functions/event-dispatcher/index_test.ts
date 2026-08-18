import { assertEquals, assertNotEquals } from "jsr:@std/assert";
import { stub } from "jsr:@std/testing/mock";
import { handleRequest, TEMPLATES } from "./index.ts";
import { FakeClient } from "../_shared/fake_supabase.ts";

function jsonRes(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function authedReq(): Request {
  return new Request("https://x/functions/v1/event-dispatcher", {
    method: "POST",
    headers: { Authorization: "Bearer test_secret" },
  });
}

const DEFAULT_DEPS = {
  phoneId: "123456",
  paymobApiKey: "pk",
  amountMultiplier: 100,
  cronSecret: "test_secret",
};

Deno.test("event-dispatcher: unauthenticated request -> 401 UNAUTHORIZED", async () => {
  const fake = new FakeClient(["event_outbox"]);
  const res = await handleRequest(
    new Request("https://x/functions/v1/event-dispatcher", { method: "POST" }),
    {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch,
      ...DEFAULT_DEPS,
    },
  );
  assertEquals(res.status, 401);
  const body = await res.json();
  assertEquals(body.error, "UNAUTHORIZED");
});

Deno.test("event-dispatcher: invalid bearer token -> 401 UNAUTHORIZED", async () => {
  const fake = new FakeClient(["event_outbox"]);
  const res = await handleRequest(
    new Request("https://x/functions/v1/event-dispatcher", {
      method: "POST",
      headers: { Authorization: "Bearer wrong_secret" },
    }),
    {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch,
      ...DEFAULT_DEPS,
    },
  );
  assertEquals(res.status, 401);
  const body = await res.json();
  assertEquals(body.error, "UNAUTHORIZED");
});

Deno.test("event-dispatcher: template param order for booking_payment_received", async () => {
  const fake = new FakeClient(["event_outbox", "whatsapp_optins"]);
  fake.seed("whatsapp_optins", [{ phone: "+201000000000", source: "BOOKING" }]);
  fake.seed("event_outbox", [
    {
      id: 1,
      handler_type: "WHATSAPP",
      payload: { phone: "+201000000000", template_name: "booking_payment_received", params: { booking_id: 12, amount: 50 } },
      status: "PENDING",
      attempts: 0,
      next_attempt_at: "2026-08-05T00:00:00Z",
    },
  ]);

  let sentBody: any;
  const fetchStub = stub(globalThis, "fetch", (_url: RequestInfo | URL, init?: RequestInit) => {
    sentBody = JSON.parse(String(init?.body));
    return Promise.resolve(jsonRes({ messages: [{ id: "wamid1" }] }));
  });

  try {
    const res = await handleRequest(authedReq(), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      ...DEFAULT_DEPS,
    });
    assertEquals(res.status, 200);
    assertEquals(sentBody.template.components[0].parameters, [
      { type: "text", text: "12" },
      { type: "text", text: "50" },
    ]);
    const row = fake.tableRows("event_outbox")[0];
    assertEquals(row.status, "SENT");
  } finally {
    fetchStub.restore();
  }
});

Deno.test("event-dispatcher: no-opt-in -> FAILED", async () => {
  const fake = new FakeClient(["event_outbox", "whatsapp_optins"]);
  fake.seed("event_outbox", [
    {
      id: 2,
      handler_type: "WHATSAPP",
      payload: { phone: "+201000000002", template_name: "booking_confirmed", params: { booking_id: 8 } },
      status: "PENDING",
      attempts: 0,
      next_attempt_at: "2026-08-05T00:00:00Z",
    },
  ]);
  const fetchStub = stub(globalThis, "fetch", () => Promise.resolve(jsonRes({})));
  try {
    const res = await handleRequest(authedReq(), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      ...DEFAULT_DEPS,
    });
    assertEquals(res.status, 200);
    assertEquals(fetchStub.calls.length, 0);
    assertEquals(fake.tableRows("event_outbox")[0].status, "FAILED");
  } finally {
    fetchStub.restore();
  }
});

Deno.test("event-dispatcher: unknown template -> FAILED", async () => {
  const fake = new FakeClient(["event_outbox", "whatsapp_optins"]);
  fake.seed("whatsapp_optins", [{ phone: "+201000000000", source: "BOOKING" }]);
  fake.seed("event_outbox", [
    {
      id: 3,
      handler_type: "WHATSAPP",
      payload: { phone: "+201000000000", template_name: "nonexistent_tmpl" },
      status: "PENDING",
      attempts: 0,
      next_attempt_at: "2026-08-05T00:00:00Z",
    },
  ]);
  const fetchStub = stub(globalThis, "fetch", () => Promise.resolve(jsonRes({})));
  try {
    const res = await handleRequest(authedReq(), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      ...DEFAULT_DEPS,
    });
    assertEquals(res.status, 200);
    assertEquals(fake.tableRows("event_outbox")[0].status, "FAILED");
  } finally {
    fetchStub.restore();
  }
});

Deno.test("event-dispatcher: unknown handler -> FAILED", async () => {
  const fake = new FakeClient(["event_outbox"]);
  fake.seed("event_outbox", [
    {
      id: 4,
      handler_type: "UNKNOWN_HANDLER",
      payload: {},
      status: "PENDING",
      attempts: 0,
      next_attempt_at: "2026-08-05T00:00:00Z",
    },
  ]);
  const fetchStub = stub(globalThis, "fetch", () => Promise.resolve(jsonRes({})));
  try {
    const res = await handleRequest(authedReq(), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      ...DEFAULT_DEPS,
    });
    assertEquals(res.status, 200);
    assertEquals(fake.tableRows("event_outbox")[0].status, "FAILED");
  } finally {
    fetchStub.restore();
  }
});

Deno.test("event-dispatcher: 5xx -> backoff PENDING with attempts+1 and next_attempt_at > now", async () => {
  const fake = new FakeClient(["event_outbox", "whatsapp_optins"]);
  fake.seed("whatsapp_optins", [{ phone: "+201000000000", source: "BOOKING" }]);
  fake.seed("event_outbox", [
    {
      id: 5,
      handler_type: "WHATSAPP",
      payload: { phone: "+201000000000", template_name: "booking_confirmed", params: { booking_id: 1 } },
      status: "PENDING",
      attempts: 1,
      next_attempt_at: "2026-08-05T00:00:00Z",
    },
  ]);
  const fetchStub = stub(globalThis, "fetch", () => Promise.resolve(jsonRes({}, 500)));
  try {
    await handleRequest(authedReq(), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      ...DEFAULT_DEPS,
    });
    const row = fake.tableRows("event_outbox")[0];
    assertEquals(row.status, "PENDING");
    assertEquals(row.attempts, 2);
    assertNotEquals(row.next_attempt_at, "2026-08-05T00:00:00Z");
  } finally {
    fetchStub.restore();
  }
});

Deno.test("event-dispatcher: 4xx -> FAILED", async () => {
  const fake = new FakeClient(["event_outbox", "whatsapp_optins"]);
  fake.seed("whatsapp_optins", [{ phone: "+201000000000", source: "BOOKING" }]);
  fake.seed("event_outbox", [
    {
      id: 6,
      handler_type: "WHATSAPP",
      payload: { phone: "+201000000000", template_name: "booking_confirmed", params: { booking_id: 1 } },
      status: "PENDING",
      attempts: 0,
      next_attempt_at: "2026-08-05T00:00:00Z",
    },
  ]);
  const fetchStub = stub(globalThis, "fetch", () => Promise.resolve(jsonRes({}, 400)));
  try {
    await handleRequest(authedReq(), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      ...DEFAULT_DEPS,
    });
    assertEquals(fake.tableRows("event_outbox")[0].status, "FAILED");
  } finally {
    fetchStub.restore();
  }
});

Deno.test("event-dispatcher: getClient throw -> 500 response", async () => {
  const fetchStub = stub(globalThis, "fetch", () => Promise.resolve(jsonRes({})));
  try {
    const res = await handleRequest(authedReq(), {
      getClient: () => { throw new Error("DB error"); },
      fetch: fetchStub,
      ...DEFAULT_DEPS,
    });
    assertEquals(res.status, 500);
  } finally {
    fetchStub.restore();
  }
});

Deno.test("event-dispatcher: PAYMOB_REFUND success sets payments REFUNDED + event SENT", async () => {
  const fake = new FakeClient(["event_outbox", "payments"]);
  fake.seed("event_outbox", [
    {
      id: 10,
      handler_type: "PAYMOB_REFUND",
      payload: { payment_id: 50, amount: 75 },
      status: "PENDING",
      attempts: 0,
      next_attempt_at: "2026-08-05T00:00:00Z",
    },
  ]);
  fake.seed("payments", [{ id: 50, status: "REFUND_PENDING", amount: 75, gateway_ref: 9988 }]);

  const urls: string[] = [];
  const fetchStub = stub(globalThis, "fetch", (url: RequestInfo | URL) => {
    const u = String(url);
    urls.push(u);
    if (u.includes("/auth/tokens")) return Promise.resolve(jsonRes({ token: "tok123" }));
    return Promise.resolve(jsonRes({ id: 111 }));
  });

  try {
    const res = await handleRequest(authedReq(), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      ...DEFAULT_DEPS,
    });
    assertEquals(res.status, 200);
    assertEquals(fake.tableRows("event_outbox")[0].status, "SENT");
    assertEquals(fake.tableRows("payments")[0].status, "REFUNDED");
  } finally {
    fetchStub.restore();
  }
});

Deno.test("event-dispatcher: PAYMOB_REFUND 4xx -> FAILED", async () => {
  const fake = new FakeClient(["event_outbox", "payments"]);
  fake.seed("event_outbox", [
    {
      id: 11,
      handler_type: "PAYMOB_REFUND",
      payload: { payment_id: 51, amount: 75 },
      status: "PENDING",
      attempts: 0,
      next_attempt_at: "2026-08-05T00:00:00Z",
    },
  ]);
  fake.seed("payments", [{ id: 51, status: "REFUND_PENDING", amount: 75, gateway_ref: 9988 }]);

  const fetchStub = stub(globalThis, "fetch", (url: RequestInfo | URL) => {
    if (String(url).includes("/auth/tokens")) return Promise.resolve(jsonRes({ token: "tok123" }));
    return Promise.resolve(jsonRes({}, 400));
  });

  try {
    await handleRequest(authedReq(), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      ...DEFAULT_DEPS,
    });
    assertEquals(fake.tableRows("event_outbox")[0].status, "FAILED");
  } finally {
    fetchStub.restore();
  }
});

Deno.test("event-dispatcher: PAYMOB_REFUND missing gateway_ref -> FAILED", async () => {
  const fake = new FakeClient(["event_outbox", "payments"]);
  fake.seed("event_outbox", [
    {
      id: 12,
      handler_type: "PAYMOB_REFUND",
      payload: { payment_id: 52, amount: 75 },
      status: "PENDING",
      attempts: 0,
      next_attempt_at: "2026-08-05T00:00:00Z",
    },
  ]);
  fake.seed("payments", [{ id: 52, status: "REFUND_PENDING", amount: 75, gateway_ref: null }]);

  const fetchStub = stub(globalThis, "fetch", () => Promise.resolve(jsonRes({})));

  try {
    await handleRequest(authedReq(), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      ...DEFAULT_DEPS,
    });
    assertEquals(fake.tableRows("event_outbox")[0].status, "FAILED");
    assertEquals(fetchStub.calls.length, 0);
  } finally {
    fetchStub.restore();
  }
});

Deno.test("event-dispatcher: PAYMOB_REFUND capped at 3 attempts (attempt 2 + 1 failure -> FAILED)", async () => {
  const fake = new FakeClient(["event_outbox", "payments"]);
  fake.seed("event_outbox", [
    {
      id: 13,
      handler_type: "PAYMOB_REFUND",
      payload: { payment_id: 53, amount: 75 },
      status: "PENDING",
      attempts: 2,
      next_attempt_at: "2026-08-05T00:00:00Z",
    },
  ]);
  fake.seed("payments", [{ id: 53, status: "REFUND_PENDING", amount: 75, gateway_ref: 9988 }]);

  const fetchStub = stub(globalThis, "fetch", (url: RequestInfo | URL) => {
    if (String(url).includes("/auth/tokens")) return Promise.resolve(jsonRes({ token: "tok123" }));
    return Promise.resolve(jsonRes({}, 500));
  });

  try {
    await handleRequest(authedReq(), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      ...DEFAULT_DEPS,
    });
    assertEquals(fake.tableRows("event_outbox")[0].status, "FAILED");
  } finally {
    fetchStub.restore();
  }
});

async function generatePemPrivateKey(): Promise<string> {
  const keyPair = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign"],
  );
  const exported = await crypto.subtle.exportKey("pkcs8", keyPair.privateKey);
  const bytes = new Uint8Array(exported);
  let binary = "";
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  const base64Key = btoa(binary);
  return `-----BEGIN PRIVATE KEY-----\n${base64Key.match(/.{1,64}/g)?.join("\n")}\n-----END PRIVATE KEY-----`;
}

Deno.test("event-dispatcher: FCM_PUSH exchanges OAuth2 token and sends FCM v1 payload", async () => {
  const fake = new FakeClient(["event_outbox"]);
  fake.seed("event_outbox", [
    {
      id: 20,
      handler_type: "FCM_PUSH",
      payload: {
        fcm_token: "token_abc_123",
        title: "Test Title",
        body: "Test Body",
        data: { booking_id: "42" },
      },
      status: "PENDING",
      attempts: 0,
      next_attempt_at: "2026-08-05T00:00:00Z",
    },
  ]);

  Deno.env.set("FCM_PROJECT_ID", "church-app-test");
  Deno.env.set("FCM_CLIENT_EMAIL", "fcm-test@church-app-test.iam.gserviceaccount.com");
  const validPem = await generatePemPrivateKey();
  Deno.env.set("FCM_PRIVATE_KEY", validPem);

  const calls: { url: string; init?: RequestInit }[] = [];
  const fetchStub = stub(globalThis, "fetch", (url: RequestInfo | URL, init?: RequestInit) => {
    const u = String(url);
    calls.push({ url: u, init });
    if (u.includes("oauth2.googleapis.com/token")) {
      return Promise.resolve(jsonRes({ access_token: "mock-fcm-access-token" }));
    }
    if (u.includes("fcm.googleapis.com/v1/projects/church-app-test/messages:send")) {
      return Promise.resolve(jsonRes({ name: "projects/church-app-test/messages/msg-1" }));
    }
    return Promise.resolve(jsonRes({}, 404));
  });

  try {
    const res = await handleRequest(authedReq(), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      ...DEFAULT_DEPS,
    });

    assertEquals(res.status, 200);
    assertEquals(calls.length, 2);
    assertEquals(calls[0].url, "https://oauth2.googleapis.com/token");
    assertEquals(calls[1].url, "https://fcm.googleapis.com/v1/projects/church-app-test/messages:send");

    const authHeader = (calls[1].init?.headers as Record<string, string>)?.["Authorization"] ?? (calls[1].init?.headers as Headers)?.get?.("Authorization");
    assertEquals(authHeader, "Bearer mock-fcm-access-token");

    const fcmBody = JSON.parse(String(calls[1].init?.body));
    assertEquals(fcmBody, {
      message: {
        token: "token_abc_123",
        notification: {
          title: "Test Title",
          body: "Test Body",
        },
        data: { booking_id: "42" },
      },
    });

    assertEquals(fake.tableRows("event_outbox")[0].status, "SENT");
  } finally {
    fetchStub.restore();
  }
});

Deno.test("event-dispatcher: FCM_PUSH invalid private key -> FAILED", async () => {
  const fake = new FakeClient(["event_outbox"]);
  fake.seed("event_outbox", [
    {
      id: 21,
      handler_type: "FCM_PUSH",
      payload: {
        fcm_token: "token_abc_123",
        title: "Test Title",
      },
      status: "PENDING",
      attempts: 0,
      next_attempt_at: "2026-08-05T00:00:00Z",
    },
  ]);

  Deno.env.set("FCM_PROJECT_ID", "church-app-test");
  Deno.env.set("FCM_CLIENT_EMAIL", "fcm-test@church-app-test.iam.gserviceaccount.com");
  Deno.env.set("FCM_PRIVATE_KEY", "invalid-pkcs8-key");

  const fetchStub = stub(globalThis, "fetch", () => Promise.resolve(jsonRes({})));

  try {
    const res = await handleRequest(authedReq(), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      ...DEFAULT_DEPS,
    });

    assertEquals(res.status, 200);
    assertEquals(fake.tableRows("event_outbox")[0].status, "FAILED");
    assertEquals(fetchStub.calls.length, 0);
  } finally {
    fetchStub.restore();
  }
});
