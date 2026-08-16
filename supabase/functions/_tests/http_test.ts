import { assertEquals, assertExists } from "jsr:@std/assert";
import { auth, respond, corsHeaders, ErrorCode, AuthUser } from "../_shared/http.ts";
import { FakeClient } from "../_shared/fake_supabase.ts";

class FakeAuthSupabaseClient extends FakeClient {
  constructor(
    tables: string[] = ["users"],
    private authUserMap: Map<string, { user: any; error: any }> = new Map(),
  ) {
    super(tables);
  }

  setAuthToken(token: string, user: any, error: any = null) {
    this.authUserMap.set(token, { user, error });
  }

  auth = {
    getUser: async (token: string) => {
      const found = this.authUserMap.get(token);
      if (!found) {
        return { data: { user: null }, error: { message: "Invalid or expired JWT", status: 401 } };
      }
      return { data: { user: found.user }, error: found.error };
    },
  };
}

Deno.test("http seam: respond() creates standard error response with CORS headers", async () => {
  const res = respond(401, "UNAUTHORIZED", "Missing credentials");
  assertEquals(res.status, 401);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");
  assertEquals(res.headers.get("Content-Type"), "application/json");

  const body = await res.json();
  assertEquals(body, {
    error: "UNAUTHORIZED",
    message: "Missing credentials",
  });
});

Deno.test("http seam: respond() creates standard error without message if omitted", async () => {
  const res = respond(500, "INTERNAL");
  assertEquals(res.status, 500);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");

  const body = await res.json();
  assertEquals(body, {
    error: "INTERNAL",
  });
});

Deno.test("http seam: respond() handles success payloads with CORS headers", async () => {
  const res = respond(200, { ok: true, data: [1, 2, 3] });
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");

  const body = await res.json();
  assertEquals(body, { ok: true, data: [1, 2, 3] });
});

Deno.test("http seam: auth() handles OPTIONS preflight request", async () => {
  const req = new Request("https://localhost/functions/v1/test", {
    method: "OPTIONS",
  });
  const res = await auth(req);
  assertEquals(res instanceof Response, true);
  if (res instanceof Response) {
    assertEquals(res.status, 200);
    assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");
  }
});

Deno.test("http seam: auth() rejects request with missing Authorization header (401)", async () => {
  const fake = new FakeAuthSupabaseClient();
  const req = new Request("https://localhost/functions/v1/test", {
    method: "POST",
  });
  const res = await auth(req, { client: fake as any });
  assertEquals(res instanceof Response, true);
  if (res instanceof Response) {
    assertEquals(res.status, 401);
    const body = await res.json();
    assertEquals(body.error, "UNAUTHORIZED");
  }
});

Deno.test("http seam: auth() rejects non-Bearer scheme (401)", async () => {
  const fake = new FakeAuthSupabaseClient();
  const req = new Request("https://localhost/functions/v1/test", {
    method: "POST",
    headers: { Authorization: "Basic dXNlcjpwYXNz" },
  });
  const res = await auth(req, { client: fake as any });
  assertEquals(res instanceof Response, true);
  if (res instanceof Response) {
    assertEquals(res.status, 401);
    const body = await res.json();
    assertEquals(body.error, "UNAUTHORIZED");
  }
});

Deno.test("http seam: auth() rejects malformed/empty token (401)", async () => {
  const fake = new FakeAuthSupabaseClient();
  const req = new Request("https://localhost/functions/v1/test", {
    method: "POST",
    headers: { Authorization: "Bearer   " },
  });
  const res = await auth(req, { client: fake as any });
  assertEquals(res instanceof Response, true);
  if (res instanceof Response) {
    assertEquals(res.status, 401);
    const body = await res.json();
    assertEquals(body.error, "UNAUTHORIZED");
  }
});

Deno.test("http seam: auth() rejects invalid or expired token (401)", async () => {
  const fake = new FakeAuthSupabaseClient();
  fake.setAuthToken("expired.token", null, { message: "JWT expired", status: 401 });

  const req = new Request("https://localhost/functions/v1/test", {
    method: "POST",
    headers: { Authorization: "Bearer expired.token" },
  });
  const res = await auth(req, { client: fake as any });
  assertEquals(res instanceof Response, true);
  if (res instanceof Response) {
    assertEquals(res.status, 401);
    const body = await res.json();
    assertEquals(body.error, "UNAUTHORIZED");
  }
});

Deno.test("http seam: auth() passes valid token and returns AuthUser", async () => {
  const fake = new FakeAuthSupabaseClient();
  fake.setAuthToken("valid.token", {
    id: "00000000-0000-0000-0000-000000000001",
    email: "user@example.com",
    role: "authenticated",
    app_metadata: { role: "USER" },
  });

  const req = new Request("https://localhost/functions/v1/test", {
    method: "POST",
    headers: { Authorization: "Bearer valid.token" },
  });
  const res = await auth(req, { client: fake as any });
  assertEquals(res instanceof Response, false);
  const user = res as AuthUser;
  assertEquals(user.id, "00000000-0000-0000-0000-000000000001");
});

Deno.test("http seam: auth() rejects non-staff user when requireStaff is true (403)", async () => {
  const fake = new FakeAuthSupabaseClient();
  fake.seed("users", [
    { id: "00000000-0000-0000-0000-000000000001", role: "USER" },
  ]);
  fake.setAuthToken("user.token", {
    id: "00000000-0000-0000-0000-000000000001",
    role: "authenticated",
  });

  const req = new Request("https://localhost/functions/v1/test", {
    method: "POST",
    headers: { Authorization: "Bearer user.token" },
  });
  const res = await auth(req, { requireStaff: true, client: fake as any });
  assertEquals(res instanceof Response, true);
  if (res instanceof Response) {
    assertEquals(res.status, 403);
    const body = await res.json();
    assertEquals(body.error, "FORBIDDEN");
  }
});

Deno.test("http seam: auth() passes staff user (ADMIN) when requireStaff is true", async () => {
  const fake = new FakeAuthSupabaseClient();
  fake.seed("users", [
    { id: "00000000-0000-0000-0000-000000000002", role: "ADMIN" },
  ]);
  fake.setAuthToken("admin.token", {
    id: "00000000-0000-0000-0000-000000000002",
    role: "authenticated",
  });

  const req = new Request("https://localhost/functions/v1/test", {
    method: "POST",
    headers: { Authorization: "Bearer admin.token" },
  });
  const res = await auth(req, { requireStaff: true, client: fake as any });
  assertEquals(res instanceof Response, false);
  const user = res as AuthUser;
  assertEquals(user.id, "00000000-0000-0000-0000-000000000002");
  assertEquals(user.role, "ADMIN");
});
