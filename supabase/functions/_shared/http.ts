import { makeServiceClient } from "./client.ts";
import { messageFor } from "./messages.ts";

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

export type ErrorCode =
  | "UNAUTHORIZED"
  | "FORBIDDEN"
  | "BAD_REQUEST"
  | "UPSTREAM_ERROR"
  | "INTERNAL";

export interface AuthUser {
  id: string;
  role?: string;
  phone?: string;
  email?: string;
  [key: string]: unknown;
}

export interface AuthOptions {
  requireStaff?: boolean;
  client?: any;
  getUser?: (token: string) => Promise<{ data: { user: any } | null; error: any }>;
}

export function respond(
  status: number,
  codeOrBody?: ErrorCode | unknown,
  message?: string,
  body?: unknown,
): Response {
  const headers = new Headers({
    ...corsHeaders,
    "Content-Type": "application/json",
  });

  if (status >= 400) {
    const errorCode = typeof codeOrBody === "string" ? codeOrBody : "INTERNAL";
    const errorBody: Record<string, unknown> = {
      error: errorCode,
      message_ar: messageFor(errorCode),
    };
    if (message !== undefined && message !== null) {
      errorBody.message = message;
    }
    if (body !== undefined && body !== null && typeof body === "object") {
      Object.assign(errorBody, body);
    }
    return new Response(JSON.stringify(errorBody), { status, headers });
  }

  if (codeOrBody !== undefined) {
    if (typeof codeOrBody === "string") {
      return new Response(codeOrBody, {
        status,
        headers: new Headers({
          ...corsHeaders,
          "Content-Type": "text/plain; charset=utf-8",
        }),
      });
    }
    return new Response(JSON.stringify(codeOrBody), { status, headers });
  }

  return new Response(null, { status, headers: new Headers(corsHeaders) });
}

function createStrictServiceClient(): any {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) {
    throw new Error(
      "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY environment variable.",
    );
  }
  return makeServiceClient(url, serviceKey);
}

export async function auth(
  req: Request,
  opts?: AuthOptions,
): Promise<Response | AuthUser> {
  if (req.method === "OPTIONS") {
    return respond(200, "ok");
  }

  const authHeader =
    req.headers.get("Authorization") ?? req.headers.get("authorization");
  if (!authHeader) {
    return respond(401, "UNAUTHORIZED", "Missing authorization header");
  }

  if (!authHeader.startsWith("Bearer ") && !authHeader.startsWith("bearer ")) {
    return respond(401, "UNAUTHORIZED", "Invalid bearer format");
  }

  const token = authHeader.slice(7).trim();
  if (!token) {
    return respond(401, "UNAUTHORIZED", "Empty bearer token");
  }

  let user: any = null;
  if (opts?.getUser) {
    const res = await opts.getUser(token);
    if (res.error || !res.data?.user) {
      return respond(
        401,
        "UNAUTHORIZED",
        res.error?.message ?? "Invalid or expired token",
      );
    }
    user = res.data.user;
  } else {
    let client: any;
    try {
      client = opts?.client ?? createStrictServiceClient();
    } catch (err) {
      console.error("Auth client initialization error:", err);
      return respond(500, "INTERNAL");
    }

    if (client?.auth?.getUser) {
      const { data, error } = await client.auth.getUser(token);
      if (error || !data?.user) {
        return respond(
          401,
          "UNAUTHORIZED",
          error?.message ?? "Invalid or expired token",
        );
      }
      user = data.user;
    } else {
      return respond(500, "INTERNAL");
    }
  }

  // Look up role exclusively from public.users table using service client
  let role: string | undefined = undefined;
  try {
    const dbClient = opts?.client ?? createStrictServiceClient();
    if (dbClient?.from) {
      const { data: profile, error: dbErr } = await dbClient
        .from("users")
        .select("role")
        .eq("id", user.id)
        .maybeSingle();

      if (dbErr || !profile?.role) {
        if (opts?.requireStaff) {
          return respond(403, "FORBIDDEN", "Staff role required");
        }
      } else {
        role = profile.role;
      }
    } else if (opts?.requireStaff) {
      return respond(403, "FORBIDDEN", "Staff role required");
    }
  } catch (err) {
    console.error("Role lookup error in users table:", err);
    if (opts?.requireStaff) {
      return respond(403, "FORBIDDEN", "Staff role required");
    }
  }

  if (opts?.requireStaff) {
    const staffRoles = ["ADMIN", "SUPER_ADMIN"];
    if (!role || !staffRoles.includes(role.toUpperCase())) {
      return respond(403, "FORBIDDEN", "Staff role required");
    }
  }

  const authUser: AuthUser = {
    id: user.id,
    email: user.email,
    phone: user.phone,
    role,
  };

  return authUser;
}

function safeCompare(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

export function verifyCronOrServiceAuth(
  req: Request,
  deps?: { cronSecret?: string; serviceRoleKey?: string },
): Response | null {
  const authHeader =
    req.headers.get("Authorization") ?? req.headers.get("authorization");
  const cronSecretHeader = req.headers.get("x-cron-secret");

  let token = "";
  if (
    authHeader &&
    (authHeader.startsWith("Bearer ") || authHeader.startsWith("bearer "))
  ) {
    token = authHeader.slice(7).trim();
  } else if (cronSecretHeader) {
    token = cronSecretHeader.trim();
  }

  if (!token) {
    return respond(401, "UNAUTHORIZED", "Missing authorization header");
  }

  const expectedSecrets = [
    deps?.cronSecret,
    deps?.serviceRoleKey,
    typeof Deno !== "undefined" ? Deno.env.get("CRON_SECRET") : undefined,
    typeof Deno !== "undefined"
      ? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
      : undefined,
  ].filter((s): s is string => typeof s === "string" && s.length > 0);

  if (expectedSecrets.length === 0) {
    console.error("No CRON_SECRET or SUPABASE_SERVICE_ROLE_KEY configured");
    return respond(500, "INTERNAL");
  }

  const matches = expectedSecrets.some((secret) => safeCompare(token, secret));
  if (!matches) {
    return respond(401, "UNAUTHORIZED", "Invalid authorization token");
  }

  return null;
}

