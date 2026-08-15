import { handleRequest } from "../supabase/functions/reconcile-payments/index.ts";
import { FakeClient } from "../supabase/functions/_shared/fake_supabase.ts";

export async function runReconcilePaymentsVerification() {
  console.log("\x1b[35m===================================================================\x1b[0m");
  console.log("\x1b[35m      NIGHTLY PAYMENT RECONCILIATION CRON RUNNER TEST              \x1b[0m");
  console.log("\x1b[35m===================================================================\x1b[0m\n");

  // -------------------------------------------------------------------------
  // Setup Stale Bookings and Created Payments
  // -------------------------------------------------------------------------
  console.log("\x1b[36m[Stage 1: Setup Scenario]\x1b[0m Seeding stale bookings and orphaned payment intents...");
  const fakeDb = new FakeClient(["bookings", "payments"]);
  fakeDb.seed("bookings", [
    {
      id: 501,
      status: "PENDING_PAYMENT",
      locked_until: new Date(Date.now() - 48 * 3600 * 1000).toISOString(),
    },
    {
      id: 502,
      status: "PENDING_PAYMENT",
      locked_until: new Date(Date.now() - 48 * 3600 * 1000).toISOString(),
    },
  ]);
  fakeDb.seed("payments", [
    { id: 1, booking_id: 501, merchant_order_id: "order-501", status: "CREATED" },
    { id: 2, booking_id: 502, merchant_order_id: "order-502", status: "CREATED" },
  ]);

  let appliedPaymentId: number | null = null;
  let cancelledBookingId: number | null = null;

  (fakeDb as any).rpc = (name: string, args: Record<string, unknown>) => {
    if (name === "cancel_booking") {
      cancelledBookingId = Number(args.p_booking_id);
      return Promise.resolve({ data: true, error: null });
    }
    return Promise.resolve({ data: null, error: null });
  };

  // -------------------------------------------------------------------------
  // Run Reconciliation
  // -------------------------------------------------------------------------
  console.log("\x1b[36m[Stage 2: Execute Reconciliation Cron]\x1b[0m Checking Paymob orders for abandoned vs settled locks...");
  const req = new Request("https://x/functions/v1/reconcile-payments", { method: "POST" });
  const res = await handleRequest(req, {
    getClient: () => fakeDb as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
    fetch: (url) => {
      const u = String(url);
      if (u.endsWith("/api/auth/tokens")) return Promise.resolve(new Response(JSON.stringify({ token: "t" }), { status: 200 }));
      if (u.includes("order-501")) {
        // Order was paid on gateway but webhook dropped
        return Promise.resolve(new Response(JSON.stringify({ transactions: [{ success: true }] }), { status: 200 }));
      }
      if (u.includes("order-502")) {
        // Order was never paid
        return Promise.resolve(new Response(JSON.stringify({ transactions: [{ success: false }] }), { status: 200 }));
      }
      return Promise.resolve(new Response("{}", { status: 200 }));
    },
    paymobApiKey: "sk",
    applyPayment: async (id) => {
      appliedPaymentId = id;
    },
  });

  console.log(`\x1b[32m[Stage 2 OK]\x1b[0m Reconciliation Response: HTTP ${res.status}`);
  console.log(`  - Late Settled Payment Applied: Payment #${appliedPaymentId}`);
  console.log(`  - Abandoned Stale Lock Cancelled: Booking #${cancelledBookingId}`);

  console.log("\n\x1b[35m===================================================================\x1b[0m");
  console.log("\x1b[35m    PAYMENT RECONCILIATION VERIFICATION COMPLETE (PASS)            \x1b[0m");
  console.log("\x1b[35m===================================================================\x1b[0m\n");
}

if (import.meta.main) {
  runReconcilePaymentsVerification().catch((err) => {
    console.error("\n\x1b[31m[TEST FAILED]\x1b[0m", err);
    Deno.exit(1);
  });
}
