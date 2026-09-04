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
  cronSecret: "test_secret",
};

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

Deno.test("event-dispatcher: FCM OAuth2 exchange HTTP error returns null and marks outbox row FAILED", async () => {
  const fake = new FakeClient(["event_outbox"]);
  fake.seed("event_outbox", [
    {
      id: 22,
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
  const validPem = await generatePemPrivateKey();
  Deno.env.set("FCM_PRIVATE_KEY", validPem);

  const fetchStub = stub(globalThis, "fetch", (url: RequestInfo | URL) => {
    const u = String(url);
    if (u.includes("oauth2.googleapis.com/token")) {
      return Promise.resolve(jsonRes({ error: "invalid_client" }, 401));
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
    assertEquals(fake.tableRows("event_outbox")[0].status, "FAILED");
  } finally {
    fetchStub.restore();
  }
});

Deno.test("event-dispatcher: FCM OAuth2 network throw returns null and marks outbox row FAILED", async () => {
  const fake = new FakeClient(["event_outbox"]);
  fake.seed("event_outbox", [
    {
      id: 23,
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
  const validPem = await generatePemPrivateKey();
  Deno.env.set("FCM_PRIVATE_KEY", validPem);

  const fetchStub = stub(globalThis, "fetch", (url: RequestInfo | URL) => {
    const u = String(url);
    if (u.includes("oauth2.googleapis.com/token")) {
      throw new TypeError("Failed to fetch");
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
    assertEquals(fake.tableRows("event_outbox")[0].status, "FAILED");
  } finally {
    fetchStub.restore();
  }
});

Deno.test("event-dispatcher: WHATSAPP booking_payment_received template sends with 2 parameters", async () => {
  const fake = new FakeClient(["event_outbox", "whatsapp_optins"]);
  fake.seed("whatsapp_optins", [
    { phone: "+201000000000" },
  ]);
  fake.seed("event_outbox", [
    {
      id: 30,
      handler_type: "WHATSAPP",
      payload: {
        phone: "+201000000000",
        template_name: "booking_payment_received",
        params: {
          booking_id: 101,
          amount: 150,
        },
      },
      status: "PENDING",
      attempts: 0,
      next_attempt_at: "2026-08-05T00:00:00Z",
    },
  ]);

  const calls: { url: string; init?: RequestInit }[] = [];
  const fetchStub = stub(globalThis, "fetch", (url: RequestInfo | URL, init?: RequestInit) => {
    calls.push({ url: String(url), init });
    return Promise.resolve(jsonRes({ messages: [{ id: "wamid.123" }] }));
  });

  try {
    const res = await handleRequest(authedReq(), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      ...DEFAULT_DEPS,
      whatsappToken: "mock-wa-token",
    });

    assertEquals(res.status, 200);
    assertEquals(calls.length, 1);
    assertEquals(calls[0].url, "https://graph.facebook.com/v20.0/123456/messages");

    const body = JSON.parse(String(calls[0].init?.body));
    assertEquals(body.template.name, "booking_payment_received");
    assertEquals(body.template.components[0].parameters, [
      { type: "text", text: "101" },
      { type: "text", text: "150" },
    ]);

    assertEquals(fake.tableRows("event_outbox")[0].status, "SENT");
  } finally {
    fetchStub.restore();
  }
});

Deno.test("event-dispatcher: WHATSAPP event_booking_payment_received template formats 5 params and sends", async () => {
  const fake = new FakeClient(["event_outbox", "whatsapp_optins"]);
  fake.seed("whatsapp_optins", [
    { phone: "+201011112222" },
  ]);
  fake.seed("event_outbox", [
    {
      id: 31,
      handler_type: "WHATSAPP",
      payload: {
        phone: "+201011112222",
        template_name: "event_booking_payment_received",
        params: {
          booking_id: "eb-uuid-1234",
          event_name: "رحلة دير الأنبا بولا",
          amount_paid_piastres: 25000,
          total_paid_piastres: 50000,
          remaining_piastres: 25000,
        },
      },
      status: "PENDING",
      attempts: 0,
      next_attempt_at: "2026-08-05T00:00:00Z",
    },
  ]);

  const calls: { url: string; init?: RequestInit }[] = [];
  const fetchStub = stub(globalThis, "fetch", (url: RequestInfo | URL, init?: RequestInit) => {
    calls.push({ url: String(url), init });
    return Promise.resolve(jsonRes({ messages: [{ id: "wamid.456" }] }));
  });

  try {
    const res = await handleRequest(authedReq(), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      ...DEFAULT_DEPS,
      whatsappToken: "mock-wa-token",
    });

    assertEquals(res.status, 200);
    assertEquals(calls.length, 1);

    const body = JSON.parse(String(calls[0].init?.body));
    assertEquals(body.template.name, "event_booking_payment_received");
    assertEquals(body.template.components[0].parameters.length, 5);
    assertEquals(body.template.components[0].parameters[0], { type: "text", text: "eb-uuid-1234" });
    assertEquals(body.template.components[0].parameters[1], { type: "text", text: "رحلة دير الأنبا بولا" });
    assertEquals(body.template.components[0].parameters[2], { type: "text", text: "25000" });

    assertEquals(fake.tableRows("event_outbox")[0].status, "SENT");
  } finally {
    fetchStub.restore();
  }
});

Deno.test("event-dispatcher: WHATSAPP network throw is isolated and marked retryable", async () => {
  const fake = new FakeClient(["event_outbox", "whatsapp_optins"]);
  fake.seed("whatsapp_optins", [
    { phone: "+201000000009" },
  ]);
  fake.seed("event_outbox", [
    {
      id: 50,
      handler_type: "WHATSAPP",
      payload: {
        phone: "+201000000009",
        template_name: "booking_confirmed",
        params: { booking_id: 77 },
      },
      status: "PENDING",
      attempts: 0,
      next_attempt_at: "2026-08-05T00:00:00Z",
    },
  ]);

  const fetchStub = stub(globalThis, "fetch", () =>
    Promise.reject(new Error("Simulated network failure"))
  );

  try {
    const res = await handleRequest(authedReq(), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      ...DEFAULT_DEPS,
      whatsappToken: "mock-wa-token",
    });

    assertEquals(res.status, 200);
    const body = await res.json();
    assertEquals(body, { ok: true, handled: 0 });

    const row = fake.tableRows("event_outbox")[0];
    assertEquals(row.status, "PENDING");
    assertEquals(row.attempts, 1);
    assertEquals(row.last_error, "Simulated network failure");
  } finally {
    fetchStub.restore();
  }
});

Deno.test("event-dispatcher: mixed batch splits status writes (SENT bulk, FAILED and PENDING individual)", async () => {
  const fake = new FakeClient(["event_outbox", "whatsapp_optins"]);
  fake.seed("whatsapp_optins", [
    { phone: "+201000000001" },
    { phone: "+201000000003" },
  ]);
  fake.seed("event_outbox", [
    {
      id: 40,
      handler_type: "WHATSAPP",
      payload: { phone: "+201000000001", template_name: "booking_confirmed", params: { booking_id: 1 } },
      status: "PENDING",
      attempts: 0,
      next_attempt_at: "2026-08-05T00:00:00Z",
    },
    {
      id: 41,
      handler_type: "WHATSAPP",
      payload: { phone: "+201000000002", template_name: "booking_confirmed", params: { booking_id: 2 } },
      status: "PENDING",
      attempts: 0,
      next_attempt_at: "2026-08-05T00:00:00Z",
    },
    {
      id: 42,
      handler_type: "WHATSAPP",
      payload: { phone: "+201000000003", template_name: "booking_confirmed", params: { booking_id: 3 } },
      status: "PENDING",
      attempts: 0,
      next_attempt_at: "2026-08-05T00:00:00Z",
    },
  ]);

  const fetchStub = stub(globalThis, "fetch", (_url: RequestInfo | URL, init?: RequestInit) => {
    const to = (JSON.parse(String(init?.body ?? "{}")) as { to?: string }).to;
    if (to === "+201000000003") {
      return Promise.reject(new Error("Simulated network failure"));
    }
    return Promise.resolve(jsonRes({ messages: [{ id: "wamid.mix" }] }));
  });

  try {
    const res = await handleRequest(authedReq(), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      ...DEFAULT_DEPS,
      whatsappToken: "mock-wa-token",
    });

    assertEquals(res.status, 200);
    const body = await res.json();
    assertEquals(body, { ok: true, handled: 1 });

    const rows = fake.tableRows("event_outbox");
    const byId = new Map(rows.map((r) => [r.id, r]));
    assertEquals(byId.get(40)?.status, "SENT");
    assertEquals(byId.get(40)?.last_error, null);
    assertEquals(byId.get(41)?.status, "FAILED");
    assertEquals(byId.get(41)?.last_error, "No WhatsApp opt-in found");
    assertEquals(byId.get(42)?.status, "PENDING");
    assertEquals(byId.get(42)?.attempts, 1);
    assertEquals(byId.get(42)?.last_error, "Simulated network failure");
  } finally {
    fetchStub.restore();
  }
});

