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

export interface PaymobCheckoutResult {
  checkoutUrl: string;
  paymobOrderId: number;
  paymentKey: string;
}

export interface PaymobRefundParams {
  transactionId: string | number;
  amountCents: number;
}

export interface PaymobRefundResult {
  success: boolean;
  raw: unknown;
}

export interface PaymobOrderStatusResult {
  id: number;
  transactions: Array<{
    id: number;
    success: boolean;
    amount_cents: number;
    [key: string]: unknown;
  }>;
  [key: string]: unknown;
}

export interface PaymobAdapter {
  session(): Promise<string>;
  checkout(params: PaymobCheckoutParams): Promise<PaymobCheckoutResult>;
  refund(params: PaymobRefundParams): Promise<PaymobRefundResult>;
  orderStatus(
    merchantOrderIdOrPaymobOrderId: string | number,
  ): Promise<PaymobOrderStatusResult>;
  hmacFields(txn: Record<string, unknown>): string;
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

export function createPaymob(opts: PaymobClientOptions): PaymobAdapter {
  const baseUrl = (opts.baseUrl ?? "https://accept.paymob.com").replace(
    /\/+$/,
    "",
  );
  const fetchFn = opts.fetch ?? fetch;

  let cachedToken: string | null = null;
  let cachedExpiresAt = 0;

  async function parseJson(res: Response): Promise<Record<string, unknown>> {
    try {
      const parsed = await res.json();
      if (typeof parsed !== "object" || parsed === null) {
        throw new Error("Invalid JSON body");
      }
      return parsed as Record<string, unknown>;
    } catch {
      throw new Error("UPSTREAM_ERROR: failed to parse JSON response");
    }
  }

  async function session(): Promise<string> {
    const now = Date.now();
    if (cachedToken && now < cachedExpiresAt - 60_000) {
      return cachedToken;
    }

    const res = await fetchFn(`${baseUrl}/api/auth/tokens`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ api_key: opts.apiKey }),
    });

    if (!res.ok) {
      throw new Error(`UPSTREAM_ERROR: HTTP ${res.status}`);
    }

    const json = await parseJson(res);
    const token = String(json.token ?? "");
    if (!token) {
      throw new Error("UPSTREAM_ERROR: token missing in auth response");
    }

    const expiresInSec =
      typeof json.expires_in === "number" ? json.expires_in : 3600;
    cachedToken = token;
    cachedExpiresAt = now + expiresInSec * 1000;
    return token;
  }

  async function checkout(
    params: PaymobCheckoutParams,
  ): Promise<PaymobCheckoutResult> {
    const token = await session();

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
      throw new Error(
        `UPSTREAM_ERROR: order creation failed with status ${orderRes.status}`,
      );
    }
    const orderJson = await parseJson(orderRes);
    const paymobOrderId = Number(orderJson.id ?? 0);
    if (!paymobOrderId) {
      throw new Error("UPSTREAM_ERROR: paymob order id missing");
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
      throw new Error(
        `UPSTREAM_ERROR: payment key creation failed with status ${keyRes.status}`,
      );
    }
    const keyJson = await parseJson(keyRes);
    const paymentKey = String(keyJson.token ?? "");
    if (!paymentKey) {
      throw new Error("UPSTREAM_ERROR: payment key missing");
    }

    const checkoutUrl = `${baseUrl}/api/acceptance/iframes/${params.iframeId}?payment_token=${paymentKey}`;

    return {
      checkoutUrl,
      paymobOrderId,
      paymentKey,
    };
  }

  async function refund(
    params: PaymobRefundParams,
  ): Promise<PaymobRefundResult> {
    const token = await session();
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
      throw new Error(`UPSTREAM_ERROR: refund failed with status ${res.status}`);
    }

    const json = await parseJson(res);
    return {
      success: true,
      raw: json,
    };
  }

  async function orderStatus(
    orderId: string | number,
  ): Promise<PaymobOrderStatusResult> {
    const token = await session();
    const res = await fetchFn(`${baseUrl}/api/ecommerce/orders/${orderId}`, {
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
    });

    if (!res.ok) {
      throw new Error(
        `UPSTREAM_ERROR: orderStatus failed with status ${res.status}`,
      );
    }

    const json = (await parseJson(res)) as unknown as PaymobOrderStatusResult;
    return json;
  }

  return {
    session,
    checkout,
    refund,
    orderStatus,
    hmacFields,
  };
}
