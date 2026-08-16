import { assertEquals } from "jsr:@std/assert";
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
