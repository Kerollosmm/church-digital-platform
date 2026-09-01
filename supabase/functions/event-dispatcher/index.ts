import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { SignJWT, importPKCS8 } from "npm:jose@5";
import { makeServiceClient } from "../_shared/client.ts";
import { respond, verifyCronOrServiceAuth } from "../_shared/http.ts";

export const TEMPLATES: Record<string, { paramCount: number }> = {
  booking_confirmed: { paramCount: 1 },
  payment_received: { paramCount: 1 },
  booking_cancelled: { paramCount: 0 },
  booking_rescheduled: { paramCount: 2 },
  booking_apology: { paramCount: 1 },
  otp_auth: { paramCount: 1 },
  booking_payment_received: { paramCount: 2 },
  booking_offer: { paramCount: 1 },
  admin_security_alert: { paramCount: 2 },
  event_booking_submitted: { paramCount: 2 },
  event_booking_confirmed: { paramCount: 5 },
  event_booking_rejected: { paramCount: 2 },
  event_booking_payment_received: { paramCount: 5 },
};
export const MAX_ATTEMPTS = 5;
export const BACKOFF_MS = 30_000;
export const DRAIN_BATCH = 10;
export const DRAIN_LIMIT = 100;

export interface Deps {
  getClient(): SupabaseClient;
  fetch: typeof fetch;
  phoneId: string;
  whatsappToken?: string;
  amountMultiplier?: number;
  fcmProjectId?: string;
  fcmClientEmail?: string;
  fcmPrivateKey?: string;
  cronSecret?: string;
  serviceRoleKey?: string;
}

type Row = {
  id: number;
  handler_type: string;
  payload: Record<string, unknown>;
  attempts: number;
};
type Result = { ok: boolean; retryable: boolean; error?: string };

async function setStatus(
  client: SupabaseClient,
  id: number,
  status: string,
  extra: Record<string, unknown> = {},
) {
  await client.from("event_outbox").update({ status, ...extra }).eq("id", id);
}

export async function sendWhatsApp(row: Row, deps: Deps): Promise<Result> {
  const client = deps.getClient();
  const { phone, template_name, params } = row.payload as {
    phone?: string;
    template_name?: string;
    params?: Record<string, unknown>;
  };
  if (!phone || !template_name) return { ok: false, retryable: false, error: "Missing phone or template_name" };
  const tmpl = TEMPLATES[template_name];
  if (!tmpl) return { ok: false, retryable: false, error: `Unknown template: ${template_name}` };
  const { data: optin } = await client
    .from("whatsapp_optins")
    .select("phone")
    .eq("phone", phone)
    .maybeSingle();
  if (!optin) return { ok: false, retryable: false, error: "No WhatsApp opt-in found" };

  const resolvedParams = params;

  const bodyParams = Array.from({ length: tmpl.paramCount }, (_, idx) => {
    let val = "";
    if (resolvedParams) {
      if (Array.isArray(resolvedParams)) {
        val = String(resolvedParams[idx] ?? "");
      } else {
        const key =
          `param${idx + 1}` in resolvedParams
            ? `param${idx + 1}`
            : String(idx + 1) in resolvedParams
            ? String(idx + 1)
            : Object.keys(resolvedParams)[idx];
        val = String(resolvedParams[key] ?? Object.values(resolvedParams)[idx] ?? "");
      }
    }
    return { type: "text", text: val };
  });
  const token =
    deps.whatsappToken ??
    (typeof Deno !== "undefined" ? Deno.env.get("WHATSAPP_TOKEN") : "") ??
    "";
  const res = await deps.fetch(
    `https://graph.facebook.com/v20.0/${deps.phoneId}/messages`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        messaging_product: "whatsapp",
        to: phone,
        type: "template",
        template: {
          name: template_name,
          language: { code: "ar" },
          components: [{ type: "body", parameters: bodyParams }],
        },
      }),
    },
  );
  if (res.ok) {
    return { ok: true, retryable: false };
  }
  return res.status >= 400 && res.status < 500
    ? { ok: false, retryable: false, error: `WhatsApp API HTTP ${res.status}` }
    : { ok: false, retryable: true, error: `WhatsApp API HTTP ${res.status}` };
}

let cachedFcmToken: { token: string; expiresAt: number; key: string } | null =
  null;

async function getFcmAccessToken(deps: Deps): Promise<string | null> {
  const projectId =
    deps.fcmProjectId ??
    (typeof Deno !== "undefined" ? Deno.env.get("FCM_PROJECT_ID") : "");
  const clientEmail =
    deps.fcmClientEmail ??
    (typeof Deno !== "undefined" ? Deno.env.get("FCM_CLIENT_EMAIL") : "");
  const privateKey =
    deps.fcmPrivateKey ??
    (typeof Deno !== "undefined" ? Deno.env.get("FCM_PRIVATE_KEY") : "");

  if (!projectId || !clientEmail || !privateKey) {
    return null;
  }

  if (
    cachedFcmToken &&
    cachedFcmToken.key === privateKey &&
    Date.now() < cachedFcmToken.expiresAt - 60_000
  ) {
    return cachedFcmToken.token;
  }

  try {
    const formattedKey = privateKey.replace(/\\n/g, "\n");
    const pkcs8Key = await importPKCS8(formattedKey, "RS256");

    const now = Math.floor(Date.now() / 1000);
    const jwt = await new SignJWT({
      scope: "https://www.googleapis.com/auth/firebase.messaging",
    })
      .setProtectedHeader({ alg: "RS256" })
      .setIssuer(clientEmail)
      .setAudience("https://oauth2.googleapis.com/token")
      .setIssuedAt(now)
      .setExpirationTime(now + 3600)
      .sign(pkcs8Key);

    const tokenRes = await deps.fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion: jwt,
      }).toString(),
    });

    if (!tokenRes.ok) {
      console.error(
        "FCM OAuth2 exchange failed:",
        tokenRes.status,
        await tokenRes.text(),
      );
      return null;
    }

    const tokenData = await tokenRes.json();
    cachedFcmToken = {
      token: tokenData.access_token,
      expiresAt: Date.now() + (tokenData.expires_in ?? 3600) * 1000,
      key: privateKey,
    };
    return cachedFcmToken.token;
  } catch (err) {
    console.error("FCM JWT signing failed:", err);
    return null;
  }
}

export async function sendFcmPush(row: Row, deps: Deps): Promise<Result> {
  const payload = row.payload as {
    fcm_token?: string;
    token?: string;
    title?: string;
    body?: string;
    notification?: { title: string; body: string };
    data?: Record<string, unknown>;
  };
  const token = payload.token ?? payload.fcm_token;
  const title = payload.notification?.title ?? payload.title;
  const body = payload.notification?.body ?? payload.body;
  const projectId =
    deps.fcmProjectId ??
    (typeof Deno !== "undefined" ? Deno.env.get("FCM_PROJECT_ID") : "");

  if (!token || !projectId) {
    return { ok: false, retryable: false, error: "Missing FCM token or FCM_PROJECT_ID" };
  }

  const accessToken = await getFcmAccessToken(deps);
  if (!accessToken) {
    return { ok: false, retryable: false, error: "Failed to obtain FCM access token" };
  }

  const notification: Record<string, string> = {};
  if (title) notification.title = title;
  if (body) notification.body = body;

  const stringData: Record<string, string> = {};
  if (payload.data) {
    for (const [k, v] of Object.entries(payload.data)) {
      stringData[k] = v == null ? "" : String(v);
    }
  }

  const fcmPayload: Record<string, unknown> = {
    message: {
      token,
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
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify(fcmPayload),
    },
  );

  if (res.ok) return { ok: true, retryable: false };
  return res.status >= 400 && res.status < 500
    ? { ok: false, retryable: false, error: `FCM API HTTP ${res.status}` }
    : { ok: false, retryable: true, error: `FCM API HTTP ${res.status}` };
}

const HANDLERS: Record<string, (row: Row, deps: Deps) => Promise<Result>> = {
  WHATSAPP: sendWhatsApp,
  FCM_PUSH: sendFcmPush,
};

export async function handleRequest(
  req: Request,
  deps: Deps,
): Promise<Response> {
  const authErr = verifyCronOrServiceAuth(req, {
    cronSecret: deps.cronSecret,
    serviceRoleKey: deps.serviceRoleKey,
  });
  if (authErr) {
    return authErr;
  }

  try {
    const client = deps.getClient();

    // Atomic batch claim via RPC
    const { data: claimed, error: rpcErr } = await client.rpc(
      "claim_event_outbox_batch",
      {
        p_batch_size: DRAIN_LIMIT,
      },
    );

    if (rpcErr) {
      console.error(
        "claim_event_outbox_batch RPC failed; aborting run",
        rpcErr,
      );
      return respond(500, "INTERNAL", "Failed to claim outbox batch");
    }

    const rows: Row[] = Array.isArray(claimed) ? (claimed as Row[]) : [];

    let handled = 0;
    for (let i = 0; i < rows.length; i += DRAIN_BATCH) {
      const results = await Promise.all(
        rows.slice(i, i + DRAIN_BATCH).map(async (row) => {
          const handler = HANDLERS[row.handler_type];
          if (!handler) {
            await setStatus(client, row.id, "FAILED", {
              last_error: `Unknown handler: ${row.handler_type}`,
            });
            return 0;
          }
          await setStatus(client, row.id, "PROCESSING");
          const outcome = await handler(row as Row, deps);
          if (outcome.ok) {
            await setStatus(client, row.id, "SENT", {
              last_error: null,
            });
            return 1;
          }
          if (!outcome.retryable) {
            await setStatus(client, row.id, "FAILED", {
              last_error: outcome.error ?? "Non-retryable failure",
            });
            return 0;
          }
          const attempts = row.attempts + 1;
          if (attempts >= MAX_ATTEMPTS) {
            await setStatus(client, row.id, "FAILED", {
              attempts,
              last_error: outcome.error ?? "Max attempts exceeded",
            });
          } else {
            const backoff = BACKOFF_MS * Math.pow(2, attempts);
            await setStatus(client, row.id, "PENDING", {
              attempts,
              next_attempt_at: new Date(Date.now() + backoff).toISOString(),
              last_error: outcome.error ?? "Retry scheduled",
            });
          }
          return 0;
        }),
      );
      handled += results.reduce((a: number, b: number) => a + b, 0);
    }
    return respond(200, { ok: true, handled });
  } catch (e) {
    console.error("event-dispatcher error", e);
    return respond(500, "INTERNAL");
  }
}

if (import.meta.main && typeof Deno !== "undefined" && Deno.serve) {
  Deno.serve((req) =>
    handleRequest(req, {
      getClient: () =>
        makeServiceClient(
          Deno.env.get("SUPABASE_URL"),
          Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
        ),
      fetch,
      phoneId: Deno.env.get("WHATSAPP_PHONE_ID")!,
      whatsappToken: Deno.env.get("WHATSAPP_TOKEN"),
      cronSecret: Deno.env.get("CRON_SECRET"),
      serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
    }),
  );
}
