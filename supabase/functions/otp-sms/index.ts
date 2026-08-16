import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";
import { respond } from "../_shared/http.ts";

export interface Deps {
  fetch: typeof fetch;
  phoneId: string;
  whatsappToken: string;
  hookSecret: string;
}

export async function handleRequest(
  req: Request,
  customDeps?: Partial<Deps>,
): Promise<Response> {
  const rawSecret =
    customDeps?.hookSecret ??
    (typeof Deno !== "undefined" ? Deno.env.get("SEND_SMS_HOOK_SECRET") : "") ??
    "";
  const secret = rawSecret.replace(/^v1,/, "").replace(/^whsec_/, "").trim();

  if (!secret) {
    return respond(401, "UNAUTHORIZED", "Missing hook secret");
  }

  const rawBody = await req.text();

  let payload: any;
  try {
    const wh = new Webhook(secret);
    const headers = Object.fromEntries(req.headers.entries());
    payload = wh.verify(rawBody, headers);
  } catch (err) {
    return respond(
      401,
      "UNAUTHORIZED",
      err instanceof Error ? err.message : String(err),
    );
  }

  const phone = payload?.user?.phone;
  const otp = payload?.sms?.otp;

  if (!phone || typeof phone !== "string" || !otp || typeof otp !== "string") {
    return respond(400, "BAD_REQUEST", "Missing phone or otp in payload");
  }

  const fetchFn = customDeps?.fetch ?? fetch;
  const phoneId =
    customDeps?.phoneId ??
    (typeof Deno !== "undefined" ? Deno.env.get("WHATSAPP_PHONE_ID") : "") ??
    "";
  const whatsappToken =
    customDeps?.whatsappToken ??
    (typeof Deno !== "undefined" ? Deno.env.get("WHATSAPP_TOKEN") : "") ??
    "";

  try {
    const res = await fetchFn(
      `https://graph.facebook.com/v20.0/${phoneId}/messages`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${whatsappToken}`,
        },
        body: JSON.stringify({
          messaging_product: "whatsapp",
          to: phone,
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
                    text: otp,
                  },
                ],
              },
            ],
          },
        }),
      },
    );

    if (res.ok) {
      return respond(200, { ok: true });
    }

    const errText = await res.text();
    let errDetails: unknown;
    try {
      errDetails = JSON.parse(errText);
    } catch {
      errDetails = errText;
    }

    const message =
      typeof errDetails === "object" &&
      errDetails !== null &&
      "error" in errDetails
        ? (errDetails as { error: unknown }).error
        : errText;

    return respond(
      502,
      "UPSTREAM_ERROR",
      typeof message === "string" ? message : JSON.stringify(message),
    );
  } catch (err) {
    return respond(
      502,
      "UPSTREAM_ERROR",
      err instanceof Error ? err.message : String(err),
    );
  }
}

if (import.meta.main && typeof Deno !== "undefined" && Deno.serve) {
  Deno.serve((req) => handleRequest(req));
}
