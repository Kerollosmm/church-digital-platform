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
