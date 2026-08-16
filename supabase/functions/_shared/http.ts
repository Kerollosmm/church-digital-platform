import { makeServiceClient } from "./client.ts";

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
  app_metadata?: Record<string, unknown>;
  user_metadata?: Record<string, unknown>;
  [key: string]: unknown;
}

export interface AuthOptions {
  requireStaff?: boolean;
  client?: any;
  getUser?: (token: string) => Promise<{ data: { user: any } | null; error: any }>;
}

export function respond(
  status: number,
  codeOrBody?: ErrorCode | Record<string, unknown> | unknown,
  message?: string,
  extra?: Record<string, unknown>,
): Response {
  const headers = new Headers({
    ...corsHeaders,
    "Content-Type": "application/json",
  });

  if (status >= 400) {
    const errorBody: Record<string, unknown> = {
      error: typeof codeOrBody === "string" ? codeOrBody : "INTERNAL",
    };
    if (message !== undefined && message !== null) {
      errorBody.message = message;
    }
    if (extra && typeof extra === "object") {
      Object.assign(errorBody, extra);
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

export async function auth(
  req: Request,
  opts?: AuthOptions,
): Promise<Response | AuthUser> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders, status: 200 });
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

  const client =
    opts?.client ??
    makeServiceClient(
      Deno.env.get("SUPABASE_URL"),
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
        Deno.env.get("SUPABASE_ANON_KEY"),
    );

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
  } else if (client?.auth?.getUser) {
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
    return respond(500, "INTERNAL", "Auth service unavailable");
  }

  let role =
    (user.app_metadata?.role as string) ??
    (user.user_metadata?.role as string) ??
    (user.role as string);

  if (client?.from) {
    try {
      const { data: profile } = await client
        .from("users")
        .select("role")
        .eq("id", user.id)
        .maybeSingle();
      if (profile?.role) {
        role = profile.role;
      }
    } catch {
      // ignore
    }
  }

  const authUser: AuthUser = {
    ...user,
    role,
  };

  if (opts?.requireStaff) {
    const staffRoles = ["ADMIN", "PRIEST", "SUPER_ADMIN"];
    if (!role || !staffRoles.includes(role.toUpperCase())) {
      return respond(403, "FORBIDDEN", "Staff role required");
    }
  }

  return authUser;
}
