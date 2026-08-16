export interface PaymobClientOptions {
  apiKey: string;
  baseUrl?: string;
  fetch?: typeof fetch;
}

export interface PaymobCheckoutParams {
  amountCents: number;
  currency?: string;
  merchantOrderId: string;
  integrationId: number;
  iframeId: number;
  billingData?: {
    first_name?: string;
    last_name?: string;
    email?: string;
    phone_number?: string;
    country?: string;
    city?: string;
    street?: string;
    building?: string;
    floor?: string;
    apartment?: string;
  };
  expiration?: number;
}

export type PaymobError = {
  ok: false;
  kind: "UPSTREAM_ERROR";
  status: number;
  message: string;
  raw?: unknown;
};

export type PaymobSessionResult =
  | { ok: true; token: string }
  | PaymobError;

export type PaymobCheckoutResult =
  | { ok: true; checkoutUrl: string; paymobOrderId: number; paymentKey: string }
  | PaymobError;

export type PaymobRefundResult =
  | { ok: true; raw: unknown }
  | PaymobError;

export type PaymobOrderStatusResult =
  | {
      ok: true;
      id: number;
      transactions: Array<{
        id: number;
        success: boolean;
        amount_cents: number;
        [key: string]: unknown;
      }>;
      [key: string]: unknown;
    }
  | PaymobError;

export interface PaymobAdapter {
  session(): Promise<PaymobSessionResult>;
  checkout(params: PaymobCheckoutParams): Promise<PaymobCheckoutResult>;
  refund(params: PaymobRefundParams): Promise<PaymobRefundResult>;
  orderStatus(
    merchantOrderIdOrPaymobOrderId: string | number,
  ): Promise<PaymobOrderStatusResult>;
  hmacFields(txn: Record<string, unknown>): string;
}

export interface PaymobRefundParams {
  transactionId: string | number;
  amountCents: number;
}

export function hmacFields(t: Record<string, unknown>): string {
  const o = (t.order ?? {}) as Record<string, unknown>;
  const s = (t.source_data ?? {}) as Record<string, unknown>;
  const str = (v: unknown) => (v == null ? "" : String(v));
  return [
    t.amount_cents,
    t.created_at,
    t.currency,
    t.error_occured,
    t.has_parent_transaction,
    t.id,
    t.integration_id,
    t.is_3d_secure,
    t.is_auth,
    t.is_capture,
    t.is_refunded,
    t.is_standalone_payment,
    t.is_voided,
    o.id,
    t.owner,
    t.pending,
    s.pan,
    s.sub_type,
    s.type,
    t.success,
  ]
    .map(str)
    .join("");
}

export async function markPaymentFailed(
  client: any,
  paymentId: number,
  opts?: { reason?: string },
): Promise<void> {
  try {
    const updatePayload: Record<string, unknown> = {
      status: "FAILED",
    };
    if (opts?.reason) {
      updatePayload.raw_webhook = {
        failure_reason: opts.reason,
        failed_at: new Date().toISOString(),
      };
    }
    await client.from("payments").update(updatePayload).eq("id", paymentId);
  } catch (err) {
    console.error(`Failed to mark payment ${paymentId} as FAILED:`, err);
  }
}

export function createPaymob(opts: PaymobClientOptions): PaymobAdapter {
  const baseUrl = (opts.baseUrl ?? "https://accept.paymob.com").replace(
    /\/+$/,
    "",
  );
  const fetchFn = opts.fetch ?? fetch;

  let cachedToken: string | null = null;
  let cachedExpiresAt = 0;

  async function parseJson(
    res: Response,
  ): Promise<
    | { ok: true; json: Record<string, unknown> }
    | { ok: false; error: PaymobError }
  > {
    try {
      const parsed = await res.json();
      if (typeof parsed !== "object" || parsed === null) {
        return {
          ok: false,
          error: {
            ok: false,
            kind: "UPSTREAM_ERROR",
            status: res.status || 502,
            message: "Invalid JSON body from Paymob upstream",
          },
        };
      }
      return { ok: true, json: parsed as Record<string, unknown> };
    } catch {
      return {
        ok: false,
        error: {
          ok: false,
          kind: "UPSTREAM_ERROR",
          status: res.status || 502,
          message: "Failed to parse JSON response from Paymob upstream",
        },
      };
    }
  }

  async function session(): Promise<PaymobSessionResult> {
    const now = Date.now();
    if (cachedToken && now < cachedExpiresAt - 60_000) {
      return { ok: true, token: cachedToken };
    }

    try {
      const res = await fetchFn(`${baseUrl}/api/auth/tokens`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ api_key: opts.apiKey }),
      });

      if (!res.ok) {
        return {
          ok: false,
          kind: "UPSTREAM_ERROR",
          status: res.status,
          message: `Paymob auth token request failed with status ${res.status}`,
        };
      }

      const parsed = await parseJson(res);
      if (!parsed.ok) return parsed.error;

      const token = String(parsed.json.token ?? "");
      if (!token) {
        return {
          ok: false,
          kind: "UPSTREAM_ERROR",
          status: 502,
          message: "Token missing in Paymob auth response",
        };
      }

      const expiresInSec =
        typeof parsed.json.expires_in === "number"
          ? parsed.json.expires_in
          : 3600;
      cachedToken = token;
      cachedExpiresAt = now + expiresInSec * 1000;
      return { ok: true, token };
    } catch (err: any) {
      return {
        ok: false,
        kind: "UPSTREAM_ERROR",
        status: 502,
        message: err?.message ?? "Network error contacting Paymob auth",
      };
    }
  }

  async function checkout(
    params: PaymobCheckoutParams,
  ): Promise<PaymobCheckoutResult> {
    const sessionRes = await session();
    if (!sessionRes.ok) return sessionRes;
    const token = sessionRes.token;

    try {
      // Step 1: Order registration
      const orderRes = await fetchFn(`${baseUrl}/api/ecommerce/orders`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          auth_token: token,
          delivery_needed: "false",
          amount_cents: String(params.amountCents),
          currency: params.currency ?? "EGP",
          merchant_order_id: String(params.merchantOrderId),
          items: [],
        }),
      });

      if (!orderRes.ok) {
        return {
          ok: false,
          kind: "UPSTREAM_ERROR",
          status: orderRes.status,
          message: `Paymob order creation failed with status ${orderRes.status}`,
        };
      }

      const orderParsed = await parseJson(orderRes);
      if (!orderParsed.ok) return orderParsed.error;

      const paymobOrderId = Number(orderParsed.json.id ?? 0);
      if (!paymobOrderId) {
        return {
          ok: false,
          kind: "UPSTREAM_ERROR",
          status: 502,
          message: "Paymob order ID missing in order creation response",
        };
      }

      // Step 2: Payment key generation
      const keyRes = await fetchFn(`${baseUrl}/api/acceptance/payment_keys`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          auth_token: token,
          amount_cents: String(params.amountCents),
          expiration: params.expiration ?? 3600,
          order_id: String(paymobOrderId),
          billing_data: {
            first_name: params.billingData?.first_name ?? "Parishioner",
            last_name: params.billingData?.last_name ?? "User",
            email: params.billingData?.email ?? "p@example.com",
            phone_number: params.billingData?.phone_number ?? "+201000000000",
            country: params.billingData?.country ?? "EG",
            city: params.billingData?.city ?? "Cairo",
            street: params.billingData?.street ?? "N/A",
            building: params.billingData?.building ?? "N/A",
            floor: params.billingData?.floor ?? "N/A",
            apartment: params.billingData?.apartment ?? "N/A",
          },
          currency: params.currency ?? "EGP",
          integration_id: params.integrationId,
        }),
      });

      if (!keyRes.ok) {
        return {
          ok: false,
          kind: "UPSTREAM_ERROR",
          status: keyRes.status,
          message: `Paymob payment key creation failed with status ${keyRes.status}`,
        };
      }

      const keyParsed = await parseJson(keyRes);
      if (!keyParsed.ok) return keyParsed.error;

      const paymentKey = String(keyParsed.json.token ?? "");
      if (!paymentKey) {
        return {
          ok: false,
          kind: "UPSTREAM_ERROR",
          status: 502,
          message: "Payment key missing in Paymob payment_keys response",
        };
      }

      const checkoutUrl = `${baseUrl}/api/acceptance/iframes/${params.iframeId}?payment_token=${paymentKey}`;

      return {
        ok: true,
        checkoutUrl,
        paymobOrderId,
        paymentKey,
      };
    } catch (err: any) {
      return {
        ok: false,
        kind: "UPSTREAM_ERROR",
        status: 502,
        message: err?.message ?? "Network error contacting Paymob checkout",
      };
    }
  }

  async function refund(
    params: PaymobRefundParams,
  ): Promise<PaymobRefundResult> {
    const sessionRes = await session();
    if (!sessionRes.ok) return sessionRes;
    const token = sessionRes.token;

    try {
      const res = await fetchFn(`${baseUrl}/api/acceptance/void_refund/refund`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          auth_token: token,
          transaction_id: String(params.transactionId),
          amount_cents: params.amountCents,
        }),
      });

      if (!res.ok) {
        return {
          ok: false,
          kind: "UPSTREAM_ERROR",
          status: res.status,
          message: `Paymob refund failed with status ${res.status}`,
        };
      }

      const parsed = await parseJson(res);
      if (!parsed.ok) return parsed.error;

      return {
        ok: true,
        raw: parsed.json,
      };
    } catch (err: any) {
      return {
        ok: false,
        kind: "UPSTREAM_ERROR",
        status: 502,
        message: err?.message ?? "Network error contacting Paymob refund",
      };
    }
  }

  async function orderStatus(
    orderId: string | number,
  ): Promise<PaymobOrderStatusResult> {
    const sessionRes = await session();
    if (!sessionRes.ok) return sessionRes;
    const token = sessionRes.token;

    try {
      const res = await fetchFn(`${baseUrl}/api/ecommerce/orders/${orderId}`, {
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
      });

      if (!res.ok) {
        return {
          ok: false,
          kind: "UPSTREAM_ERROR",
          status: res.status,
          message: `Paymob orderStatus failed with status ${res.status}`,
        };
      }

      const parsed = await parseJson(res);
      if (!parsed.ok) return parsed.error;

      return {
        ok: true,
        ...(parsed.json as any),
      };
    } catch (err: any) {
      return {
        ok: false,
        kind: "UPSTREAM_ERROR",
        status: 502,
        message: err?.message ?? "Network error contacting Paymob orderStatus",
      };
    }
  }

  return {
    session,
    checkout,
    refund,
    orderStatus,
    hmacFields,
  };
}
