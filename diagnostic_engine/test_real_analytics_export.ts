import { handleRequest, sanitizeCsvCell, buildCsv } from "../supabase/functions/analytics-export/index.ts";
import { FakeClient } from "../supabase/functions/_shared/fake_supabase.ts";

export async function runAnalyticsExportVerification(): Promise<void> {


  // -------------------------------------------------------------------------
  // Stage 1: Formula Injection Sanitization
  // -------------------------------------------------------------------------
  console.log("\x1b[36m[Stage 1: CSV Formula Injection Protection]\x1b[0m Sanitizing dangerous spreadsheet prefixes...");
  const maliciousCells = ["=cmd|' /C calc'!A0", "+SUM(A1:A10)", "-2+3", "@SUM(A1)"];
  for (const cell of maliciousCells) {
    const sanitized = sanitizeCsvCell(cell);
    if (!sanitized.startsWith("'")) {
      throw new Error(`SECURITY VULNERABILITY: Cell \`${cell}\` was not sanitized against CSV formula injection!`);
    }
  }
  console.log(`\x1b[32m[Stage 1 OK]\x1b[0m All malicious spreadsheet prefixes safely escaped.`);

  // -------------------------------------------------------------------------
  // Stage 2: Admin RBAC & CSV Export Execution
  // -------------------------------------------------------------------------
  console.log("\n\x1b[36m[Stage 2: Admin RBAC Export Execution]\x1b[0m Requesting payments ledger CSV export...");
  const fakeDb = new FakeClient(["users", "v_analytics_payments"]);
  fakeDb.seed("users", [{ id: "admin-uid-1", role: "ADMIN" }]);
  fakeDb.seed("v_analytics_payments", [
    { payment_id: 1, created_at: "2026-08-01", amount: 50, status: "PAID", booking_id: 10, payment_method: "CARD" },
    { payment_id: 2, created_at: "2026-08-02", amount: 20, status: "PAID", booking_id: 11, payment_method: "CARD" },
  ]);

  const req = new Request("https://x/functions/v1/analytics-export?report=payments", {
    method: "GET",
    headers: { Authorization: "Bearer admin-token" },
  });

  const res = await handleRequest(req, {
    getServiceClient: () => fakeDb as any,
    getUserClient: () => fakeDb as any,
    getUser: () => Promise.resolve({ data: { user: { id: "admin-uid-1" } as any }, error: null }),
  });

  if (res.status !== 200) {
    throw new Error(`Analytics export failed with status ${res.status}`);
  }

  const csvContent = await res.text();
  console.log(`\x1b[32m[Stage 2 OK]\x1b[0m CSV Export Generated (Length: ${csvContent.length} bytes):`);
  console.log("-------------------------------------------------------------------");
  console.log(csvContent.trim());
  console.log("-------------------------------------------------------------------");

  console.log("\n\x1b[35m===================================================================\x1b[0m");
  console.log("\x1b[35m    ADMIN ANALYTICS EXPORT VERIFICATION COMPLETE (PASS)            \x1b[0m");
  console.log("\x1b[35m===================================================================\x1b[0m\n");
}

if (import.meta.main) {
  runAnalyticsExportVerification().catch((err) => {
    console.error("\n\x1b[31m[TEST FAILED]\x1b[0m", err);
    Deno.exit(1);
  });
}
