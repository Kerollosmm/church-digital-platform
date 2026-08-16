import { assertEquals } from "jsr:@std/assert";
import type { SupabaseClient, User } from "npm:@supabase/supabase-js@2";
import { buildCsv, exportAllowed, handleRequest, sanitizeCsvCell, type Deps } from "./index.ts";
import { FakeClient } from "../_shared/fake_supabase.ts";

Deno.test("sanitizeCsvCell sanitizes formula injection characters (=, +, -, @, \\t, \\r)", () => {
  assertEquals(sanitizeCsvCell("=1+1"), "'=1+1");
  assertEquals(sanitizeCsvCell("+100"), "'+100");
  assertEquals(sanitizeCsvCell("-50"), "'-50");
  assertEquals(sanitizeCsvCell("@SUM(A1)"), "'@SUM(A1)");
  assertEquals(sanitizeCsvCell("\tTAB_VAL"), "'\tTAB_VAL");
  assertEquals(sanitizeCsvCell("\rCR_VAL"), "'\rCR_VAL");
  assertEquals(sanitizeCsvCell("normal_text"), "normal_text");
});

Deno.test("builds CSV from rows with BOM + formula-char guard", () => {
  const csv = buildCsv(
    ["month", "rate_pct"],
    [["2026-08-01", "50.00"], ["2026-09-01", "66.67"], ["=1+1", "-0.50"]],
  );
  assertEquals(csv, "\uFEFFmonth,rate_pct\n2026-08-01,50.00\n2026-09-01,66.67\n'=1+1,'-0.50\n");
});

Deno.test("exportAllowed allows staff roles (ADMIN, PRIEST, SUPER_ADMIN) and denies USER", () => {
  assertEquals(exportAllowed("USER"), false);
  assertEquals(exportAllowed("ADMIN"), true);
  assertEquals(exportAllowed("PRIEST"), true);
  assertEquals(exportAllowed("SUPER_ADMIN"), true);
});

function createDeps(overrides: Partial<Deps> = {}): { deps: Deps; fakeAnon: FakeClient; fakeService: FakeClient } {
  const fakeAnon = new FakeClient(["users"]);
  fakeAnon.seed("users", [{ id: "user-1", role: "ADMIN" }]);
  const fakeService = new FakeClient(["v_analytics_utilization", "v_analytics_payments", "v_analytics_bookings"]);
  fakeService.seed("v_analytics_utilization", [{ month: "2026-08", count: 10 }]);

  const deps: Deps = {
    getServiceClient: () => fakeService as unknown as SupabaseClient,
    getUserClient: (_token: string) => fakeAnon as unknown as SupabaseClient,
    getUser: async (token: string) => {
      if (token === "valid-token") {
        return { data: { user: { id: "user-1" } as User }, error: null };
      }
      return { data: { user: null }, error: { message: "Invalid token" } };
    },
    ...overrides,
  };
  return { deps, fakeAnon, fakeService };
}

Deno.test("analytics-export: non-GET -> 400 BAD_REQUEST JSON", async () => {
  const { deps } = createDeps();
  const res = await handleRequest(new Request("https://x/analytics-export", { method: "POST" }), deps);
  assertEquals(res.status, 400);
  const body = await res.json();
  assertEquals(body.error, "BAD_REQUEST");
});

Deno.test("analytics-export: unknown report -> 400 BAD_REQUEST JSON", async () => {
  const { deps } = createDeps();
  const res = await handleRequest(new Request("https://x/analytics-export?report=invalid", {
    method: "GET",
    headers: { Authorization: "Bearer valid-token" },
  }), deps);
  assertEquals(res.status, 400);
  const body = await res.json();
  assertEquals(body.error, "BAD_REQUEST");
});

Deno.test("analytics-export: no token -> 401 UNAUTHORIZED JSON", async () => {
  const { deps } = createDeps();
  const res = await handleRequest(new Request("https://x/analytics-export?report=utilization", { method: "GET" }), deps);
  assertEquals(res.status, 401);
  const body = await res.json();
  assertEquals(body.error, "UNAUTHORIZED");
});

Deno.test("analytics-export: garbage token -> 401 UNAUTHORIZED JSON", async () => {
  const { deps } = createDeps();
  const req = new Request("https://x/analytics-export?report=utilization", {
    method: "GET",
    headers: { Authorization: "Bearer garbage-token" },
  });
  const res = await handleRequest(req, deps);
  assertEquals(res.status, 401);
  const body = await res.json();
  assertEquals(body.error, "UNAUTHORIZED");
});

Deno.test("analytics-export: role USER -> 403 FORBIDDEN JSON", async () => {
  const { deps, fakeAnon } = createDeps();
  fakeAnon.seed("users", [{ id: "user-1", role: "USER" }]);
  const req = new Request("https://x/analytics-export?report=utilization", {
    method: "GET",
    headers: { Authorization: "Bearer valid-token" },
  });
  const res = await handleRequest(req, deps);
  assertEquals(res.status, 403);
  const body = await res.json();
  assertEquals(body.error, "FORBIDDEN");
});

Deno.test("analytics-export: role ADMIN -> 200 CSV", async () => {
  const { deps } = createDeps();
  const req = new Request("https://x/analytics-export?report=utilization", {
    method: "GET",
    headers: { Authorization: "Bearer valid-token" },
  });
  const res = await handleRequest(req, deps);
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("Content-Type"), "text/csv; charset=utf-8");
  assertEquals(res.headers.get("Content-Disposition"), 'attachment; filename="utilization-.csv"');
  assertEquals(await res.text(), "\uFEFFmonth,count\n2026-08,10\n");
});

Deno.test("analytics-export: empty rows header is 'empty'", async () => {
  const { deps, fakeService } = createDeps();
  fakeService.seed("v_analytics_utilization", []);
  const req = new Request("https://x/analytics-export?report=utilization", {
    method: "GET",
    headers: { Authorization: "Bearer valid-token" },
  });
  const res = await handleRequest(req, deps);
  assertEquals(res.status, 200);
  assertEquals(await res.text(), "\uFEFFempty\n");
});

Deno.test("analytics-export: month filter filters rows by month", async () => {
  const { deps, fakeService } = createDeps();
  fakeService.seed("v_analytics_utilization", [
    { month: "2026-08", count: 10 },
    { month: "2026-07", count: 5 },
  ]);
  const req = new Request("https://x/analytics-export?report=utilization&month=2026-08", {
    method: "GET",
    headers: { Authorization: "Bearer valid-token" },
  });
  const res = await handleRequest(req, deps);
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("Content-Disposition"), 'attachment; filename="utilization-2026-08.csv"');
  const body = await res.text();
  assertEquals(body, "\uFEFFmonth,count\n2026-08,10\n");
});

Deno.test("analytics-export: date range filtering with from and to query params", async () => {
  const { deps, fakeService } = createDeps();
  fakeService.seed("v_analytics_utilization", [
    { month: "2026-01-01", count: 5 },
    { month: "2026-03-15", count: 10 },
    { month: "2026-07-01", count: 20 },
  ]);
  const req = new Request("https://x/analytics-export?report=utilization&from=2026-01-01&to=2026-06-30", {
    method: "GET",
    headers: { Authorization: "Bearer valid-token" },
  });
  const res = await handleRequest(req, deps);
  assertEquals(res.status, 200);
  const text = await res.text();
  assertEquals(text, "\uFEFFmonth,count\n2026-01-01,5\n2026-03-15,10\n");
});
