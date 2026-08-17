import { assertEquals, assertNotEquals } from "jsr:@std/assert";
import { stub } from "jsr:@std/testing/mock";
import { handleRequest, TEMPLATES } from "./index.ts";
import { FakeClient } from "../_shared/fake_supabase.ts";

function jsonRes(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

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
    const res = await handleRequest(new Request("https://x/functions/v1/event-dispatcher", { method: "POST" }), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      phoneId: "123456",
      paymobApiKey: "pk",
      amountMultiplier: 100,
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
    const res = await handleRequest(new Request("https://x/functions/v1/event-dispatcher", { method: "POST" }), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      phoneId: "123456",
      paymobApiKey: "pk",
      amountMultiplier: 100,
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
    const res = await handleRequest(new Request("https://x/functions/v1/event-dispatcher", { method: "POST" }), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      phoneId: "123456",
      paymobApiKey: "pk",
      amountMultiplier: 100,
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
    const res = await handleRequest(new Request("https://x/functions/v1/event-dispatcher", { method: "POST" }), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      phoneId: "123456",
      paymobApiKey: "pk",
      amountMultiplier: 100,
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
    await handleRequest(new Request("https://x/functions/v1/event-dispatcher", { method: "POST" }), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      phoneId: "123456",
      paymobApiKey: "pk",
      amountMultiplier: 100,
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
    await handleRequest(new Request("https://x/functions/v1/event-dispatcher", { method: "POST" }), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      phoneId: "123456",
      paymobApiKey: "pk",
      amountMultiplier: 100,
    });
    assertEquals(fake.tableRows("event_outbox")[0].status, "FAILED");
  } finally {
    fetchStub.restore();
  }
});

Deno.test("event-dispatcher: getClient throw -> 500 response", async () => {
  const fetchStub = stub(globalThis, "fetch", () => Promise.resolve(jsonRes({})));
  try {
    const res = await handleRequest(new Request("https://x/functions/v1/event-dispatcher", { method: "POST" }), {
      getClient: () => { throw new Error("DB error"); },
      fetch: fetchStub,
      phoneId: "123456",
      paymobApiKey: "pk",
      amountMultiplier: 100,
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
    const res = await handleRequest(new Request("https://x/functions/v1/event-dispatcher", { method: "POST" }), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      phoneId: "123456",
      paymobApiKey: "pk",
      amountMultiplier: 100,
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
    await handleRequest(new Request("https://x/functions/v1/event-dispatcher", { method: "POST" }), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      phoneId: "123456",
      paymobApiKey: "pk",
      amountMultiplier: 100,
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
    await handleRequest(new Request("https://x/functions/v1/event-dispatcher", { method: "POST" }), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      phoneId: "123456",
      paymobApiKey: "pk",
      amountMultiplier: 100,
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
    await handleRequest(new Request("https://x/functions/v1/event-dispatcher", { method: "POST" }), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      phoneId: "123456",
      paymobApiKey: "pk",
      amountMultiplier: 100,
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
    const res = await handleRequest(new Request("https://x/functions/v1/event-dispatcher", { method: "POST" }), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      phoneId: "123456",
      paymobApiKey: "pk",
      amountMultiplier: 100,
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
    const res = await handleRequest(new Request("https://x/functions/v1/event-dispatcher", { method: "POST" }), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      phoneId: "123456",
      paymobApiKey: "pk",
      amountMultiplier: 100,
    });

    assertEquals(res.status, 200);
    assertEquals(fake.tableRows("event_outbox")[0].status, "FAILED");
    assertEquals(fetchStub.calls.length, 0);
  } finally {
    fetchStub.restore();
  }
});

Deno.test("event-dispatcher: video_ready template sends WhatsApp and stamps link_sent_at", async () => {
  const fake = new FakeClient(["event_outbox", "whatsapp_optins", "videos", "video_purchases"]);
  fake.seed("whatsapp_optins", [{ phone: "+201099990060", source: "BOOKING" }]);
  fake.seed("videos", [
    {
      id: 101,
      title_ar: "فيديو المعمودية",
      yt_url: "https://youtu.be/baptism101",
      privacy: "UNLISTED",
      price: 0,
    },
  ]);
  fake.seed("video_purchases", [
    {
      id: 501,
      video_id: 101,
      user_id: "00000000-0000-0000-0000-000000000060",
      payment_id: 901,
      access_granted_at: "2026-08-17T00:00:00Z",
      link_sent_at: null,
    },
  ]);
  fake.seed("event_outbox", [
    {
      id: 50,
      handler_type: "WHATSAPP",
      payload: {
        phone: "+201099990060",
        template_name: "video_ready",
        video_id: 101,
        purchase_id: 501,
      },
      status: "PENDING",
      attempts: 0,
      next_attempt_at: "2026-08-05T00:00:00Z",
    },
  ]);

  let sentBody: any;
  const fetchStub = stub(globalThis, "fetch", (_url: RequestInfo | URL, init?: RequestInit) => {
    sentBody = JSON.parse(String(init?.body));
    return Promise.resolve(jsonRes({ messages: [{ id: "wamid_video_101" }] }));
  });

  try {
    const res = await handleRequest(new Request("https://x/functions/v1/event-dispatcher", { method: "POST" }), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      phoneId: "123456",
      paymobApiKey: "pk",
      amountMultiplier: 100,
    });

    assertEquals(res.status, 200);
    assertEquals(sentBody.template.name, "video_ready");
    assertEquals(sentBody.template.components[0].parameters, [
      { type: "text", text: "https://youtu.be/baptism101" },
    ]);
    const outboxRow = fake.tableRows("event_outbox")[0];
    assertEquals(outboxRow.status, "SENT");

    const purchaseRow = fake.tableRows("video_purchases")[0];
    assertNotEquals(purchaseRow.link_sent_at, null);
  } finally {
    fetchStub.restore();
  }
});



