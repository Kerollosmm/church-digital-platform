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

Deno.test("http seam: respond() creates standard error response with CORS headers and message_ar", async () => {
  const res = respond(401, "UNAUTHORIZED", "Missing credentials");
  assertEquals(res.status, 401);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");
  assertEquals(res.headers.get("Content-Type"), "application/json");

  const body = await res.json();
  assertEquals(body, {
    error: "UNAUTHORIZED",
    message_ar: "انتهت الجلسة، من فضلك سجل الدخول مرة أخرى.",
  });
});

Deno.test("http seam: respond() error body carries NO message field even when supplied (zero-leak)", async () => {
  const res = respond(401, "UNAUTHORIZED", "GoTrue internal: JWT signature mismatch 8812");
  const body = await res.json();
  assertEquals(Object.keys(body).sort(), ["error", "message_ar"]);
  assertEquals(body.message, undefined);
});

Deno.test("http seam: respond() creates standard error with message_ar when message is omitted", async () => {
  const res = respond(500, "INTERNAL");
  assertEquals(res.status, 500);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");

  const body = await res.json();
  assertEquals(body, {
    error: "INTERNAL",
    message_ar: "حدث خطأ في النظام، يرجى المحاولة لاحقاً.",
  });
});

Deno.test("http seam: every 4xx/5xx respond() body contains non-empty message_ar", async () => {
  const codes: ErrorCode[] = ["UNAUTHORIZED", "FORBIDDEN", "BAD_REQUEST", "UPSTREAM_ERROR", "INTERNAL"];
  for (const code of codes) {
    const res = respond(400, code);
    const body = await res.json();
    assertEquals(typeof body.message_ar, "string");
    assertEquals(body.message_ar.length > 0, true);
  }
});

Deno.test("http seam: unknown error code receives FALLBACK message_ar", async () => {
  const res = respond(400, "CUSTOM_UNKNOWN_CODE" as any);
  const body = await res.json();
  assertEquals(body.error, "CUSTOM_UNKNOWN_CODE");
  assertEquals(body.message_ar, "حدث خطأ غير متوقع، حاول مرة أخرى.");
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

Deno.test("http seam: auth() rejects spoofed user_metadata.role SUPER_ADMIN when DB users.role is USER (403)", async () => {
  const fake = new FakeAuthSupabaseClient();
  fake.seed("users", [
    { id: "00000000-0000-0000-0000-000000000001", role: "USER" },
  ]);
  fake.setAuthToken("spoofed.token", {
    id: "00000000-0000-0000-0000-000000000001",
    role: "authenticated",
    user_metadata: { role: "SUPER_ADMIN" },
    app_metadata: { role: "SUPER_ADMIN" },
  });

  const req = new Request("https://localhost/functions/v1/test", {
    method: "POST",
    headers: { Authorization: "Bearer spoofed.token" },
  });
  const res = await auth(req, { requireStaff: true, client: fake as any });
  assertEquals(res instanceof Response, true);
  if (res instanceof Response) {
    assertEquals(res.status, 403);
    const body = await res.json();
    assertEquals(body.error, "FORBIDDEN");
  }
});

Deno.test("http seam: auth() rejects request when role lookup throws/fails (403)", async () => {
  const fake = new FakeAuthSupabaseClient();
  fake.from = () => {
    throw new Error("DB connection failure");
  };
  fake.setAuthToken("valid.token", {
    id: "00000000-0000-0000-0000-000000000001",
    role: "authenticated",
  });

  const req = new Request("https://localhost/functions/v1/test", {
    method: "POST",
    headers: { Authorization: "Bearer valid.token" },
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



Deno.test("http seam: auth() token failure leaks NO library message into body (zero-leak)", async () => {
  const fake = new FakeAuthSupabaseClient();
  fake.setAuthToken("bad.token", null, {
    message: "GoTrue internal: JWT signature mismatch 8812",
    status: 401,
  });
  const res = await auth(
    new Request("https://x/functions/v1/x", {
      method: "POST",
      headers: { Authorization: "Bearer bad.token" },
    }),
    { client: fake },
  ) as Response;
  assertEquals(res.status, 401);
  const body = await res.json();
  assertEquals(Object.keys(body).sort(), ["error", "message_ar"]);
  const raw = JSON.stringify(body);
  assertEquals(raw.includes("GoTrue"), false, "library message leaked");
  assertEquals(raw.includes("8812"), false, "internal detail leaked");
});
