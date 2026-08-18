import type { SupabaseClient, User } from "npm:@supabase/supabase-js@2";
import { createClient } from "npm:@supabase/supabase-js@2";
import { makeServiceClient } from "../_shared/client.ts";
import { auth, respond } from "../_shared/http.ts";
import {
  createPaymob,
  markPaymentFailed,
} from "../_shared/paymob.ts";

export interface Deps {
  getClient(): unknown;
  fetch: typeof fetch;
  paymobApiKey: string;
  integrationId: number;
  iframeId: number;
  amountMultiplier: number;
  getUser?: (
    token: string,
  ) => Promise<{ data: { user: User | null }; error: unknown }>;
  client?: unknown;
}

export async function handleRequest(
  req: Request,
  deps?: Deps,
): Promise<Response> {
  const authRes = await auth(req, {
    client: deps?.client ?? (deps?.getClient ? deps.getClient() : undefined),
    getUser: deps?.getUser,
  });
  if (authRes instanceof Response) return authRes;
  const callerUser = authRes;

  try {
    const body = (await req.json().catch(() => ({}))) as Record<
      string,
      unknown
    >;
    const paymentId = Number(body.payment_id ?? 0);
    const bookingId = Number(body.booking_id ?? 0);

    const supabase = (
      deps?.getClient
        ? deps.getClient()
        : makeServiceClient(
            Deno.env.get("SUPABASE_URL"),
            Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
          )
    ) as SupabaseClient;

    let orderId: number;
    let amountCents: number;
    let createdPaymentId: number | null = null;

    const amountMultiplier = deps?.amountMultiplier ?? 100;

    if (paymentId > 0) {
      const { data: pay, error: pErr } = await supabase
        .from("payments")
        .select("id, amount, booking_id")
        .eq("id", paymentId)
        .single();
      if (pErr || !pay) {
        return respond(404, "BAD_REQUEST", "Payment not found");
      }

      if (callerUser && pay.booking_id) {
        const { data: b } = await supabase
          .from("bookings")
          .select("user_id")
          .eq("id", pay.booking_id)
          .maybeSingle();
        if (b && b.user_id && b.user_id !== callerUser.id) {
          return respond(403, "FORBIDDEN");
        }
      }

      orderId = pay.id as number;
      amountCents = Math.round((pay.amount as number) * amountMultiplier);
    } else if (bookingId > 0) {
      if (!Number.isInteger(bookingId)) {
        return respond(400, "BAD_REQUEST", "Invalid booking_id");
      }
      const { data: b, error: bErr } = await supabase
        .from("bookings")
        .select("id, user_id, paid_amount, slot_id")
        .eq("id", bookingId)
        .single();
      if (bErr || !b) {
        return respond(404, "BAD_REQUEST", "Booking not found");
      }

      if (callerUser && b.user_id && b.user_id !== callerUser.id) {
        return respond(403, "FORBIDDEN");
      }

      let amount = (b.paid_amount as number) || 0;
      if (amount === 0 && b.slot_id) {
        const { data: slot } = await supabase
          .from("service_slots")
          .select("price")
          .eq("id", b.slot_id)
          .single();
        if (slot?.price) amount = slot.price;
      }
      amountCents = Math.round(amount * amountMultiplier);
      const { data: pay, error: pErr } = await supabase
        .from("payments")
        .insert({
          booking_id: bookingId,
          amount,
          status: "CREATED",
          gateway_ref: null,
        })
        .select()
        .single();
      if (pErr) throw pErr;
      orderId = pay.id as number;
      createdPaymentId = orderId;
    } else {
      return respond(
        400,
        "BAD_REQUEST",
        "booking_id or payment_id is required",
      );
    }

    await supabase
      .from("payments")
      .update({ merchant_order_id: String(orderId) })
      .eq("id", orderId);

    const apiKey = deps?.paymobApiKey ?? Deno.env.get("PAYMOB_API_KEY") ?? "";
    const integrationId =
      deps?.integrationId ??
      Number(Deno.env.get("PAYMOB_INTEGRATION_ID") ?? "0");
    const iframeId =
      deps?.iframeId ?? Number(Deno.env.get("PAYMOB_IFRAME_ID") ?? "0");

    const paymob = createPaymob({
      apiKey,
      fetch: deps?.fetch,
    });

    const checkoutResult = await paymob.checkout({
      amountCents,
      merchantOrderId: String(orderId),
      integrationId,
      iframeId,
    });

    if (!checkoutResult.ok) {
      if (createdPaymentId) {
        await markPaymentFailed(supabase, createdPaymentId, {
          reason: checkoutResult.message,
        });
      }
      return respond(
        502,
        "UPSTREAM_ERROR",
        checkoutResult.message || "Paymob upstream error",
      );
    }

    return respond(200, {
      checkout_url: checkoutResult.checkoutUrl,
      payment_id: orderId,
    });
  } catch (e) {
    console.error("paymob-checkout error", e);
    return respond(500, "INTERNAL");
  }
}

if (import.meta.main && typeof Deno !== "undefined" && Deno.serve) {
  const paymobApiKey = Deno.env.get("PAYMOB_API_KEY");
  const integrationIdStr = Deno.env.get("PAYMOB_INTEGRATION_ID");
  const iframeIdStr = Deno.env.get("PAYMOB_IFRAME_ID");
  const hmacSecret = Deno.env.get("PAYMOB_HMAC_SECRET") ?? Deno.env.get("PAYMOB_HMAC_KEY");

  if (!paymobApiKey || paymobApiKey.trim() === "" || paymobApiKey === "0") {
    throw new Error("Missing or invalid PAYMOB_API_KEY environment variable.");
  }
  if (!integrationIdStr || integrationIdStr.trim() === "" || integrationIdStr === "0") {
    throw new Error("Missing or invalid PAYMOB_INTEGRATION_ID environment variable.");
  }
  if (!iframeIdStr || iframeIdStr.trim() === "" || iframeIdStr === "0") {
    throw new Error("Missing or invalid PAYMOB_IFRAME_ID environment variable.");
  }
  if (!hmacSecret || hmacSecret.trim() === "" || hmacSecret === "0") {
    throw new Error("Missing or invalid PAYMOB_HMAC_SECRET environment variable.");
  }

  const integrationId = Number(integrationIdStr);
  const iframeId = Number(iframeIdStr);

  Deno.serve((req) =>
    handleRequest(req, {
      getClient: () =>
        makeServiceClient(
          Deno.env.get("SUPABASE_URL"),
          Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
        ),
      getUser: async (token: string) => {
        const client = createClient(
          Deno.env.get("SUPABASE_URL")!,
          Deno.env.get("SUPABASE_ANON_KEY")!,
        );
        return await client.auth.getUser(token);
      },
      fetch,
      paymobApiKey,
      integrationId,
      iframeId,
      amountMultiplier: 100,
    }),
  );
}
