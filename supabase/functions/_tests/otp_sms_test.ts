import { assertEquals } from "jsr:@std/assert";
import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";
import { handleRequest } from "../otp-sms/index.ts";

const SECRET = `whsec_${btoa("0123456789abcdef0123456789abcdef")}`;

function signedRequest(payload: unknown): Request {
  const wh = new Webhook(SECRET);
  const body = JSON.stringify(payload);
  const msgId = "msg_test_1";
  const ts = Math.floor(Date.now() / 1000);
  const sig = wh.sign(msgId, new Date(ts * 1000), body);
  return new Request("https://x/functions/v1/otp-sms", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "webhook-id": msgId,
      "webhook-timestamp": String(ts),
      "webhook-signature": sig,
    },
    body,
  });
}

Deno.test("otp-sms: upstream Meta error leaks NO provider payload (zero-leak)", async () => {
  const metaError = {
    error: {
      message: "(#131030) Recipient phone number not in allowed list",
      type: "OAuthException",
      code: 131030,
      error_data: { messaging_product: "whatsapp", details: "WL:613" },
    },
  };
  let called = 0;
  const res = await handleRequest(signedRequest({
    user: { phone: "+201000000001" },
    sms: { otp: "123456" },
  }), {
    hookSecret: SECRET,
    phoneId: "PHONE1",
    whatsappToken: "TOK",
    fetch: () => {
      called++;
      return Promise.resolve(new Response(JSON.stringify(metaError), { status: 400 }));
    },
  });

  assertEquals(called, 1);
  assertEquals(res.status, 502);
  const body = await res.json();
  assertEquals(Object.keys(body).sort(), ["error", "message_ar"]);
  assertEquals(body.error, "UPSTREAM_ERROR");
  const raw = JSON.stringify(body);
  assertEquals(raw.includes("131030"), false, "provider code leaked");
  assertEquals(raw.includes("Recipient"), false, "provider message leaked");
});

Deno.test("otp-sms: webhook verification failure leaks NO library/secret detail", async () => {
  const req = new Request("https://x/functions/v1/otp-sms", {
    method: "POST",
    headers: { "Content-Type": "application/json", "webhook-signature": "v1,bad" },
    body: JSON.stringify({ user: { phone: "+201000000001" }, sms: { otp: "123456" } }),
  });
  const res = await handleRequest(req, {
    hookSecret: SECRET,
    phoneId: "P",
    whatsappToken: "T",
    fetch: () => Promise.resolve(new Response("{}", { status: 200 })),
  });
  assertEquals(res.status, 401);
  const body = await res.json();
  assertEquals(Object.keys(body).sort(), ["error", "message_ar"]);
  const raw = JSON.stringify(body);
  assertEquals(raw.includes(SECRET), false, "secret leaked");
  assertEquals(raw.toLowerCase().includes("signature"), false, "library detail leaked");
});

Deno.test("otp-sms: network throw returns bare UPSTREAM_ERROR", async () => {
  const res = await handleRequest(signedRequest({
    user: { phone: "+201000000001" },
    sms: { otp: "123456" },
  }), {
    hookSecret: SECRET,
    phoneId: "P",
    whatsappToken: "T",
    fetch: () => Promise.reject(new TypeError("fetch failed: ECONNREFUSED 127.0.0.1:443")),
  });
  assertEquals(res.status, 502);
  const body = await res.json();
  assertEquals(Object.keys(body).sort(), ["error", "message_ar"]);
  const raw = JSON.stringify(body);
  assertEquals(raw.includes("ECONNREFUSED"), false, "network detail leaked");
});

Deno.test("otp-sms: success path unaffected", async () => {
  const res = await handleRequest(signedRequest({
    user: { phone: "+201000000001" },
    sms: { otp: "123456" },
  }), {
    hookSecret: SECRET,
    phoneId: "P",
    whatsappToken: "T",
    fetch: () => Promise.resolve(new Response("{}", { status: 200 })),
  });
  assertEquals(res.status, 200);
});
