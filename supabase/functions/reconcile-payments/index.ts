import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { makeServiceClient } from "../_shared/client.ts";
import { respond } from "../_shared/http.ts";
import { createPaymob, PaymobOrderStatusResult } from "../_shared/paymob.ts";

export interface Deps {
  getClient(): unknown;
  fetch: typeof fetch;
  paymobApiKey: string;
  applyPayment: (paymentId: number) => Promise<void>;
}

export async function handleRequest(
  _req: Request,
  deps: Deps,
): Promise<Response> {
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

      let order: PaymobOrderStatusResult;
      try {
        order = await paymob.orderStatus(pay.merchant_order_id);
      } catch (upstreamErr) {
        console.warn(
          `Upstream Paymob error for payment ${pay.id}:`,
          upstreamErr,
        );
        continue;
      }

      if (!order || !Array.isArray(order.transactions)) {
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
        await supabase
          .from("payments")
          .update({ status: "FAILED" })
          .eq("id", pay.id);
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
  Deno.serve((req) =>
    handleRequest(req, {
      getClient: () =>
        makeServiceClient(
          Deno.env.get("SUPABASE_URL"),
          Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
        ),
      fetch,
      paymobApiKey: Deno.env.get("PAYMOB_API_KEY")!,
      applyPayment: async (id) => {
        const sb = makeServiceClient(
          Deno.env.get("SUPABASE_URL"),
          Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
        );
        const { error } = await sb.rpc("apply_payment", { p_payment_id: id });
        if (error) throw error;
      },
    }),
  );
}
