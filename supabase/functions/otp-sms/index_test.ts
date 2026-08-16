import { assertEquals } from "jsr:@std/assert";
import { stub } from "jsr:@std/testing/mock";
import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";
import { handleRequest } from "./index.ts";

const TEST_SECRET_RAW = "v1,whsec_Mf2wR9RmM86T0ZvuW8edG8+0k20l9u10=";
const TEST_SECRET_BASE64 = "Mf2wR9RmM86T0ZvuW8edG8+0k20l9u10=";

function createSignedRequest(
  payloadStr: string,
  secretBase64 = TEST_SECRET_BASE64,
  msgId = "msg_test_123",
  timestamp = new Date(),
): Request {
  const wh = new Webhook(secretBase64);
  const sig = wh.sign(msgId, timestamp, payloadStr);
  const tsStr = String(Math.floor(timestamp.getTime() / 1000));
  return new Request("https://localhost/functions/v1/otp-sms", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "webhook-id": msgId,
      "webhook-timestamp": tsStr,
      "webhook-signature": sig,
    },
    body: payloadStr,
  });
}

function jsonRes(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.test("otp-sms: valid signed webhook sends WhatsApp template message and returns 200", async () => {
  const payloadObj = {
    user: { phone: "+201234567890" },
    sms: { otp: "561166" },
  };
  const payloadStr = JSON.stringify(payloadObj);
  const req = createSignedRequest(payloadStr, TEST_SECRET_BASE64);

  let capturedUrl = "";
  let capturedInit: RequestInit | undefined;

  const fetchStub = stub(
    globalThis,
    "fetch",
    (url: RequestInfo | URL, init?: RequestInit) => {
      capturedUrl = String(url);
      capturedInit = init;
      return Promise.resolve(jsonRes({ messages: [{ id: "wamid.123" }] }, 200));
    },
  );

  try {
    const res = await handleRequest(req, {
      fetch: fetchStub,
      phoneId: "phone_12345",
      whatsappToken: "token_abc123",
      hookSecret: TEST_SECRET_RAW,
    });

    assertEquals(res.status, 200);
    const resBody = await res.json();
    assertEquals(resBody.ok, true);

    assertEquals(
      capturedUrl,
      "https://graph.facebook.com/v20.0/phone_12345/messages",
    );
    assertEquals(capturedInit?.method, "POST");

    const headers = capturedInit?.headers as Record<string, string>;
    assertEquals(headers["Content-Type"], "application/json");
    assertEquals(headers["Authorization"], "Bearer token_abc123");

    const sentBody = JSON.parse(String(capturedInit?.body));
    assertEquals(sentBody, {
      messaging_product: "whatsapp",
      to: "+201234567890",
      type: "template",
      template: {
        name: "otp_auth",
        language: { code: "ar" },
        components: [
          {
            type: "body",
            parameters: [
              {
                type: "text",
                text: "561166",
              },
            ],
          },
        ],
      },
    });
  } finally {
    fetchStub.restore();
  }
});

Deno.test("otp-sms: invalid or missing signature returns 401 UNAUTHORIZED", async () => {
  const payloadStr = JSON.stringify({
    user: { phone: "+201234567890" },
    sms: { otp: "561166" },
  });

  const req = new Request("https://localhost/functions/v1/otp-sms", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "webhook-id": "msg_bad",
      "webhook-timestamp": String(Math.floor(Date.now() / 1000)),
      "webhook-signature": "v1,invalid_sig",
    },
    body: payloadStr,
  });

  const fetchStub = stub(globalThis, "fetch", () =>
    Promise.resolve(jsonRes({}))
  );

  try {
    const res = await handleRequest(req, {
      fetch: fetchStub,
      phoneId: "phone_12345",
      whatsappToken: "token_abc123",
      hookSecret: TEST_SECRET_RAW,
    });

    assertEquals(res.status, 401);
    const body = await res.json();
    assertEquals(body.error, "UNAUTHORIZED");
    assertEquals(fetchStub.calls.length, 0);
  } finally {
    fetchStub.restore();
  }
});

Deno.test("otp-sms: missing phone or otp returns 400 BAD_REQUEST", async () => {
  const payloadObj = {
    user: { phone: "+201234567890" },
    sms: {}, // missing otp
  };
  const payloadStr = JSON.stringify(payloadObj);
  const req = createSignedRequest(payloadStr, TEST_SECRET_BASE64);

  const fetchStub = stub(globalThis, "fetch", () =>
    Promise.resolve(jsonRes({}))
  );

  try {
    const res = await handleRequest(req, {
      fetch: fetchStub,
      phoneId: "phone_12345",
      whatsappToken: "token_abc123",
      hookSecret: TEST_SECRET_RAW,
    });

    assertEquals(res.status, 400);
    const resBody = await res.json();
    assertEquals(resBody.error, "BAD_REQUEST");
    assertEquals(fetchStub.calls.length, 0);
  } finally {
    fetchStub.restore();
  }
});

Deno.test("otp-sms: Meta API non-2xx returns 502 UPSTREAM_ERROR", async () => {
  const payloadObj = {
    user: { phone: "+201234567890" },
    sms: { otp: "999888" },
  };
  const payloadStr = JSON.stringify(payloadObj);
  const req = createSignedRequest(payloadStr, TEST_SECRET_BASE64);

  const metaErrorBody = {
    error: {
      message: "Invalid OAuth access token",
      type: "OAuthException",
      code: 190,
    },
  };

  const fetchStub = stub(globalThis, "fetch", () =>
    Promise.resolve(jsonRes(metaErrorBody, 401))
  );

  try {
    const res = await handleRequest(req, {
      fetch: fetchStub,
      phoneId: "phone_12345",
      whatsappToken: "token_invalid",
      hookSecret: TEST_SECRET_RAW,
    });

    assertEquals(res.status, 502);
    const resBody = await res.json();
    assertEquals(resBody.error, "UPSTREAM_ERROR");
  } finally {
    fetchStub.restore();
  }
});
