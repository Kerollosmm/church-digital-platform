import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { makeServiceClient } from "../_shared/client.ts";
import { respond, verifyCronOrServiceAuth } from "../_shared/http.ts";
import { createPaymob, markPaymentFailed } from "../_shared/paymob.ts";

export interface Deps {
  getClient(): unknown;
  fetch: typeof fetch;
  paymobApiKey: string;
  applyPayment: (paymentId: number) => Promise<void>;
  cronSecret?: string;
  serviceRoleKey?: string;
}

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
    const supabase = deps.getClient() as SupabaseClient;
    const { data: bookings, error } = await supabase
      .from("bookings")
      .select("id, paid_amount")
      .eq("status", "PENDING_PAYMENT")
      .lt(
        "locked_until",
        new Date(Date.now() - 24 * 3600 * 1000).toISOString(),
      );
    if (error) throw error;

    const { data: pays, error: pErr } = await supabase
      .from("payments")
      .select("id, booking_id, merchant_order_id")
      .eq("status", "CREATED");
    if (pErr) throw pErr;

    const paymob = createPaymob({
      apiKey: deps.paymobApiKey,
      fetch: deps.fetch,
    });

    let resolved = 0;
    for (const pay of pays ?? []) {
      const stale = (bookings ?? []).some(
        (b: { id: unknown }) => b.id === pay.booking_id,
      );
      if (!stale || !pay.merchant_order_id) continue;

      const order = await paymob.orderStatus(pay.merchant_order_id);
      if (!order.ok) {
        console.error(
          `[INCIDENT] Upstream Paymob orderStatus failure for payment ${pay.id} (merchant_order_id=${pay.merchant_order_id}): HTTP ${order.status} ${order.message}`,
        );
        // T058: Transient failure leaves payment CREATED; do not markPaymentFailed.
        continue;
      }

      if (!Array.isArray(order.transactions)) {
        continue;
      }

      const paid = (
        order.transactions as Array<{ success?: boolean }>
      ).some((t) => t.success);
      if (paid) {
        await deps.applyPayment(pay.id as number);
        resolved++;
      } else {
        await supabase.rpc("cancel_booking", {
          p_booking_id: pay.booking_id,
        });
        try {
          await markPaymentFailed(supabase, pay.id as number, {
            reason: "unpaid_on_reconcile",
          });
        } catch (markErr) {
          console.error(
            `[INCIDENT] mark_payment_failed RPC failed for payment ${pay.id}:`,
            markErr,
          );
        }
        resolved++;
      }
    }
    return respond(200, { ok: true, resolved });
  } catch (e) {
    console.error("reconcile error", e);
    return respond(500, "INTERNAL");
  }
}

if (import.meta.main && typeof Deno !== "undefined" && Deno.serve) {
  const apiKey = Deno.env.get("PAYMOB_API_KEY");
  if (!apiKey) {
    throw new Error("Missing PAYMOB_API_KEY environment variable.");
  }
  Deno.serve((req) =>
    handleRequest(req, {
      getClient: () =>
        makeServiceClient(
          Deno.env.get("SUPABASE_URL"),
          Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
        ),
      fetch,
      paymobApiKey: apiKey,
      applyPayment: async (id) => {
        const sb = makeServiceClient(
          Deno.env.get("SUPABASE_URL"),
          Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
        );
        const { error } = await sb.rpc("apply_payment", { p_payment_id: id });
        if (error) throw error;
      },
      cronSecret: Deno.env.get("CRON_SECRET"),
      serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
    }),
  );
}
