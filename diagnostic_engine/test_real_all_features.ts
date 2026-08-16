import { runRealPaymentVerification } from "./test_real_payment_flow.ts";
import { runHighConcurrencyVerification } from "./test_real_high_concurrency.ts";
import { runEventDispatcherVerification } from "./test_real_event_dispatcher.ts";
import { runReconcilePaymentsVerification } from "./test_real_reconcile_payments.ts";
import { runYoutubeExpiryVerification } from "./test_real_youtube_expiry.ts";
import { runOfflineSyncVerification } from "./test_real_offline_sync.ts";
import { runAnalyticsExportVerification } from "./test_real_analytics_export.ts";
import { runSocialLinksVerification } from "./test_real_social_links.ts";

async function runMasterVerificationSuite() {
  console.log("\x1b[35m###################################################################\x1b[0m");
  console.log("\x1b[35m#                                                                 #\x1b[0m");
  console.log("\x1b[35m#   UNIFIED REAL-WORLD BACKEND FEATURE & HIGH-CONCURRENCY SUITE   #\x1b[0m");
  console.log("\x1b[35m#                                                                 #\x1b[0m");
  console.log("\x1b[35m###################################################################\x1b[0m\n");

  const suites = [
    { name: "Live Payment & Settlement Invariants", fn: runRealPaymentVerification },
    { name: "High-Concurrency Atomic Booking Engine", fn: runHighConcurrencyVerification },
    { name: "Event Outbox & Multi-Channel Dispatcher", fn: runEventDispatcherVerification },
    { name: "Nightly Payment Reconciliation Cron", fn: runReconcilePaymentsVerification },
    { name: "YouTube Sermon Video Expiry Sweep", fn: runYoutubeExpiryVerification },
    { name: "Offline Mutation Batch Sync Engine", fn: runOfflineSyncVerification },
    { name: "Admin Analytics & Sanitized CSV Export", fn: runAnalyticsExportVerification },
    { name: "Church Directory & Social Links RLS", fn: runSocialLinksVerification },
  ];

  const results: Array<{ name: string; status: "PASS" | "FAIL"; durationMs: number; error?: string }> = [];

  for (const s of suites) {
    const start = Date.now();
    console.log(`\n\x1b[34m>>> STARTING SUITE: ${s.name}...\x1b[0m`);
    try {
      await s.fn();
      const durationMs = Date.now() - start;
      results.push({ name: s.name, status: "PASS", durationMs });
      console.log(`\x1b[32m>>> SUITE COMPLETED: ${s.name} (PASS in ${durationMs}ms)\x1b[0m\n`);
    } catch (err: any) {
      const durationMs = Date.now() - start;
      results.push({ name: s.name, status: "FAIL", durationMs, error: err.message });
      console.error(`\x1b[31m>>> SUITE FAILED: ${s.name} (${err.message})\x1b[0m\n`);
    }
  }

  // Summary Table
  console.log("\n\x1b[35m===================================================================\x1b[0m");
  console.log("\x1b[35m                 MASTER VERIFICATION SCORECARD                     \x1b[0m");
  console.log("\x1b[35m===================================================================\x1b[0m\n");

  console.log("| Suite Name | Status | Latency |");
  console.log("|---|---|---|");
  for (const r of results) {
    const icon = r.status === "PASS" ? "✅ PASS" : "❌ FAIL";
    console.log(`| **${r.name}** | ${icon} | ${r.durationMs}ms |`);
  }

  const passedCount = results.filter((r) => r.status === "PASS").length;
  const failedCount = results.filter((r) => r.status === "FAIL").length;

  console.log(`\n\x1b[32mTotal Passed: ${passedCount} / ${suites.length}\x1b[0m | \x1b[${failedCount > 0 ? "31" : "32"}mTotal Failed: ${failedCount}\x1b[0m\n`);

  if (failedCount > 0) {
    Deno.exit(1);
  }
}

if (import.meta.main) {
  runMasterVerificationSuite().catch((err) => {
    console.error("Master suite crash:", err);
    Deno.exit(1);
  });
}
