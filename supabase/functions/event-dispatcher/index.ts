import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { SignJWT, importPKCS8 } from "npm:jose@5";
import { makeServiceClient } from "../_shared/client.ts";

export const TEMPLATES: Record<string, { paramCount: number }> = {
  booking_confirmed: { paramCount: 1 },
  payment_received: { paramCount: 1 },
  booking_cancelled: { paramCount: 0 },
  booking_rescheduled: { paramCount: 2 },
  booking_apology: { paramCount: 1 },
  otp_auth: { paramCount: 1 },
  booking_payment_received: { paramCount: 2 },
  booking_offer: { paramCount: 1 },
};
export const MAX_ATTEMPTS = 5;
export const REFUND_MAX_ATTEMPTS = 3;
export const BACKOFF_MS = 30_000;
export const DRAIN_BATCH = 10;
export const DRAIN_LIMIT = 100;

export interface Deps {
  getClient(): SupabaseClient;
  fetch: typeof fetch;
  phoneId: string;
  whatsappToken?: string;
  paymobApiKey: string;
  amountMultiplier: number;
  fcmProjectId?: string;
  fcmClientEmail?: string;
  fcmPrivateKey?: string;
}

type Row = { id: number; handler_type: string; payload: Record<string, unknown>; attempts: number };
type Result = { ok: boolean; retryable: boolean };

async function setStatus(client: SupabaseClient, id: number, status: string, extra: Record<string, unknown> = {}) {
  await client.from("event_outbox").update({ status, ...extra }).eq("id", id);
}

export async function sendWhatsApp(row: Row, deps: Deps): Promise<Result> {
  const client = deps.getClient();
  const { phone, template_name, params } = row.payload as { phone?: string; template_name?: string; params?: Record<string, unknown> };
  if (!phone || !template_name) return { ok: false, retryable: false };
  const tmpl = TEMPLATES[template_name];
  if (!tmpl) return { ok: false, retryable: false };
  const { data: optin } = await client.from("whatsapp_optins").select("phone").eq("phone", phone).maybeSingle();
  if (!optin) return { ok: false, retryable: false };
  const bodyParams = Array.from({ length: tmpl.paramCount }, (_, idx) => {
    let val = "";
    if (params) {
      if (Array.isArray(params)) {
        val = String(params[idx] ?? "");
      } else {
        const key = `param${idx + 1}` in params ? `param${idx + 1}` : (String(idx + 1) in params ? String(idx + 1) : Object.keys(params)[idx]);
        val = String(params[key] ?? Object.values(params)[idx] ?? "");
      }
    }
    return { type: "text", text: val };
  });
  const token = deps.whatsappToken ?? (typeof Deno !== "undefined" ? Deno.env.get("WHATSAPP_TOKEN") : "") ?? "";
  const res = await deps.fetch(`https://graph.facebook.com/v20.0/${deps.phoneId}/messages`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      messaging_product: "whatsapp", to: phone, type: "template",
      template: { name: template_name, language: { code: "ar" }, components: [{ type: "body", parameters: bodyParams }] },
    }),
  });
  if (res.ok) return { ok: true, retryable: false };
  return res.status >= 400 && res.status < 500 ? { ok: false, retryable: false } : { ok: false, retryable: true };
}


export async function triggerPaymobRefund(row: Row, deps: Deps): Promise<Result> {
  const client = deps.getClient();
  const { payment_id, amount } = row.payload as { payment_id?: number; amount?: number };
  if (!payment_id || !amount) return { ok: false, retryable: false };
  const { data: pay } = await client.from("payments").select("gateway_ref").eq("id", payment_id).single();
  if (!pay?.gateway_ref) return { ok: false, retryable: false };
  const authRes = await deps.fetch("https://accept.paymob.com/api/auth/tokens", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ api_key: deps.paymobApiKey }),
  });
  const authJson = (await authRes.json()) as Record<string, unknown>;
  const res = await deps.fetch("https://accept.paymob.com/api/acceptance/void_refund/refund", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ auth_token: String(authJson.token ?? ""), transaction_id: pay.gateway_ref, amount_cents: Math.round(Number(amount) * deps.amountMultiplier) }),
  });
  if (res.ok) {
    await client.from("payments").update({ status: "REFUNDED" }).eq("id", payment_id);
    return { ok: true, retryable: false };
  }
  return res.status >= 400 && res.status < 500 ? { ok: false, retryable: false } : { ok: false, retryable: true };
}

export async function sendFcmPush(row: Row, deps: Deps): Promise<Result> {
  const payload = row.payload as {
    fcm_token?: string;
    title?: string;
    body?: string;
    data?: Record<string, unknown>;
  };
  const { fcm_token, title, body, data } = payload;
  const projectId = deps.fcmProjectId ?? Deno.env.get("FCM_PROJECT_ID");
  const clientEmail = deps.fcmClientEmail ?? Deno.env.get("FCM_CLIENT_EMAIL");
  const privateKey = deps.fcmPrivateKey ?? Deno.env.get("FCM_PRIVATE_KEY");

  if (!fcm_token || !projectId || !clientEmail || !privateKey) {
    return { ok: false, retryable: false };
  }

  let jwt: string;
  try {
    const formattedKey = privateKey.replace(/\\n/g, "\n");
    const key = await importPKCS8(formattedKey, "RS256");
    jwt = await new SignJWT({
      scope: "https://www.googleapis.com/auth/firebase.messaging",
    })
      .setProtectedHeader({ alg: "RS256" })
      .setIssuer(clientEmail)
      .setAudience("https://oauth2.googleapis.com/token")
      .setExpirationTime("1h")
      .setIssuedAt()
      .sign(key);
  } catch (e) {
    console.error("FCM JWT signing failed:", e);
    return { ok: false, retryable: false };
  }

  const tokRes = await deps.fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }).toString(),
  });

  if (!tokRes.ok) {
    return tokRes.status >= 400 && tokRes.status < 500
      ? { ok: false, retryable: false }
      : { ok: false, retryable: true };
  }

  const tokJson = (await tokRes.json()) as { access_token?: string };
  if (!tokJson.access_token) {
    return { ok: false, retryable: false };
  }

  const notification: Record<string, string> = {};
  if (title) notification.title = title;
  if (body) notification.body = body;

  const stringData: Record<string, string> = {};
  if (data) {
    for (const [k, v] of Object.entries(data)) {
      stringData[k] = v == null ? "" : String(v);
    }
  }

  const fcmPayload: Record<string, unknown> = {
    message: {
      token: fcm_token,
      ...(Object.keys(notification).length > 0 ? { notification } : {}),
      ...(Object.keys(stringData).length > 0 ? { data: stringData } : {}),
    },
  };

  const res = await deps.fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${tokJson.access_token}`,
      },
      body: JSON.stringify(fcmPayload),
    },
  );

  if (res.ok) return { ok: true, retryable: false };
  return res.status >= 400 && res.status < 500
    ? { ok: false, retryable: false }
    : { ok: false, retryable: true };
}

const HANDLERS: Record<string, (row: Row, deps: Deps) => Promise<Result>> = {
  WHATSAPP: sendWhatsApp,
  PAYMOB_REFUND: triggerPaymobRefund,
  FCM_PUSH: sendFcmPush,
};

export async function handleRequest(_req: Request, deps: Deps): Promise<Response> {
  const cors = { "Access-Control-Allow-Origin": "*" };
  try {
    const client = deps.getClient();
    const { data: queue, error } = await client.from("event_outbox")
      .select("id, handler_type, payload, attempts")
      .eq("status", "PENDING").lte("next_attempt_at", new Date().toISOString())
      .order("created_at", { ascending: true }).limit(DRAIN_LIMIT);
    if (error) throw error;
    let handled = 0;
    const rows = queue ?? [];
    for (let i = 0; i < rows.length; i += DRAIN_BATCH) {
      const results = await Promise.all(rows.slice(i, i + DRAIN_BATCH).map(async (row) => {
        const handler = HANDLERS[row.handler_type];
        if (!handler) { await setStatus(client, row.id, "FAILED"); return 0; }
        await setStatus(client, row.id, "PROCESSING");
        const outcome = await handler(row as Row, deps);
        if (outcome.ok) { await setStatus(client, row.id, "SENT"); return 1; }
        if (!outcome.retryable) { await setStatus(client, row.id, "FAILED"); return 0; }
        const attempts = row.attempts + 1;
        if (attempts >= (row.handler_type === "PAYMOB_REFUND" ? REFUND_MAX_ATTEMPTS : MAX_ATTEMPTS)) {
          await setStatus(client, row.id, "FAILED");
        } else {
          const backoff = row.handler_type === "PAYMOB_REFUND" ? 0 : BACKOFF_MS * Math.pow(2, attempts);
          await setStatus(client, row.id, "PENDING", { attempts, next_attempt_at: new Date(Date.now() + backoff).toISOString() });
        }
        return 0;
      }));
      handled += results.reduce((a: number, b: number) => a + b, 0);
    }
    return new Response(JSON.stringify({ ok: true, handled }), { status: 200, headers: cors });
  } catch (e) {
    console.error("event-dispatcher error", e);
    return new Response(JSON.stringify({ error: "INTERNAL" }), { status: 500, headers: cors });
  }
}

if (import.meta.main && typeof Deno !== "undefined" && Deno.serve) {
  Deno.serve((req) => handleRequest(req, {
    getClient: () => makeServiceClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")),
    fetch,
    phoneId: Deno.env.get("WHATSAPP_PHONE_ID")!,
    whatsappToken: Deno.env.get("WHATSAPP_TOKEN"),
    paymobApiKey: Deno.env.get("PAYMOB_API_KEY")!,
    amountMultiplier: 100,
  }));
}

