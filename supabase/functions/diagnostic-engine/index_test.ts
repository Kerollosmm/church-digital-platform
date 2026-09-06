import { assertEquals, assertStringIncludes } from "jsr:@std/assert";
import { handleRequest } from "./index.ts";
import { FakeClient } from "../_shared/fake_supabase.ts";

Deno.test("diagnostic-engine: rejects missing Authorization header (401)", async () => {
  const req = new Request("https://x/functions/v1/diagnostic-engine", {
    method: "POST",
  });
  const res = await handleRequest(req, {
    client: new FakeClient(["users"]),
  });
  assertEquals(res.status, 401);
  const body = await res.json();
  assertEquals(body.error, "UNAUTHORIZED");
});

Deno.test("diagnostic-engine: rejects non-staff role USER with 403 FORBIDDEN", async () => {
  const fake = new FakeClient(["users"]);
  fake.seed("users", [{ id: "user-1", role: "USER" }]);
  const req = new Request("https://x/functions/v1/diagnostic-engine", {
    method: "POST",
    headers: { Authorization: "Bearer valid-token" },
  });
  const res = await handleRequest(req, {
    client: fake,
    getUser: () => Promise.resolve({ data: { user: { id: "user-1" } as any }, error: null }),
  });
  assertEquals(res.status, 403);
  const body = await res.json();
  assertEquals(body.error, "FORBIDDEN");
});

Deno.test("diagnostic-engine: allows ADMIN staff and executes diagnostics", async () => {
  const fake = new FakeClient(["users", "bookings", "event_outbox"]);
  fake.seed("users", [{ id: "admin-1", role: "ADMIN" }]);
  const req = new Request("https://x/functions/v1/diagnostic-engine", {
    method: "POST",
    headers: { Authorization: "Bearer admin-token" },
  });
  const res = await handleRequest(req, {
    client: fake,
    serviceClient: fake,
    anonClient: fake,
    getUser: () => Promise.resolve({ data: { user: { id: "admin-1" } as any }, error: null }),
  });
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.success, true);
  assertEquals(typeof body.probes_executed, "number");
});

Deno.test("diagnostic-engine: enqueues admin alert with dispatcher-compatible params", async () => {
  const fake = new FakeClient(["users", "bookings", "event_outbox"]);
  fake.seed("users", [{ id: "admin-1", role: "ADMIN" }]);
  const req = new Request("https://x/functions/v1/diagnostic-engine", {
    method: "POST",
    headers: { Authorization: "Bearer admin-token" },
  });
  const res = await handleRequest(req, {
    client: fake,
    serviceClient: fake,
    anonClient: fake,
    getUser: () => Promise.resolve({ data: { user: { id: "admin-1" } as any }, error: null }),
    alertPhone: "+201000000000",
  });
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.critical_count, 3);
  const rows = fake.tableRows("event_outbox");
  assertEquals(rows.length, 1);
  assertEquals(rows[0].handler_type, "WHATSAPP");
  const payload = rows[0].payload as Record<string, unknown>;
  assertEquals(payload.phone, "+201000000000");
  assertEquals(payload.template_name, "admin_security_alert");
  const params = payload.params as Record<string, string>;
  assertEquals(params.param1, "3");
  assertStringIncludes(params.param2, "Anonymous SELECT permitted");
});

Deno.test("diagnostic-engine: alert skipped when no alert phone configured", async () => {
  Deno.env.delete("DIAGNOSTIC_ALERT_PHONE");
  const fake = new FakeClient(["users", "bookings", "event_outbox"]);
  fake.seed("users", [{ id: "admin-1", role: "ADMIN" }]);
  const req = new Request("https://x/functions/v1/diagnostic-engine", {
    method: "POST",
    headers: { Authorization: "Bearer admin-token" },
  });
  const res = await handleRequest(req, {
    client: fake,
    serviceClient: fake,
    anonClient: fake,
    getUser: () => Promise.resolve({ data: { user: { id: "admin-1" } as any }, error: null }),
  });
  assertEquals(res.status, 200);
  assertEquals(fake.tableRows("event_outbox").length, 0);
});
