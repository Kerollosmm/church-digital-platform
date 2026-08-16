import type { SupabaseClient, User } from "npm:@supabase/supabase-js@2";
import { createClient } from "npm:@supabase/supabase-js@2";
import { makeServiceClient } from "../_shared/client.ts";
import { auth, respond, corsHeaders } from "../_shared/http.ts";

export interface Deps {
  getServiceClient?: () => SupabaseClient;
  getUserClient?: (token: string) => SupabaseClient;
  getUser?: (token: string) => Promise<{ data: { user: User | null }; error: unknown }>;
  client?: SupabaseClient;
}

export function sanitizeCsvCell(v: string): string {
  return /^[=+\-@\t\r]/.test(v) ? "'" + v : v;
}

export function buildCsv(headers: string[], rows: string[][]): string {
  const esc = (v: string) => {
    const s = sanitizeCsvCell(v);
    return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  return (
    "\uFEFF" +
    [headers.map(esc).join(","), ...rows.map((r) => r.map(esc).join(","))].join(
      "\n",
    ) +
    "\n"
  );
}

export function exportAllowed(role: string | undefined): boolean {
  return role?.toUpperCase() === "ADMIN";
}

export async function handleRequest(
  req: Request,
  deps?: Deps,
): Promise<Response> {
  if (req.method !== "GET") {
    return respond(400, "BAD_REQUEST", "Method not allowed");
  }

  const token = (
    req.headers.get("Authorization") ??
    req.headers.get("authorization") ??
    ""
  ).replace(/^Bearer\s+/i, "");
  const authClient =
    deps?.client ??
    (deps?.getUserClient ? deps.getUserClient(token) : undefined);

  const authRes = await auth(req, {
    requireStaff: true,
    client: authClient,
    getUser: deps?.getUser,
  });
  if (authRes instanceof Response) return authRes;

  if (!exportAllowed(authRes.role)) {
    return respond(403, "FORBIDDEN", "Admin role required");
  }

  const url = new URL(req.url);
  const report = url.searchParams.get("report") ?? "";
  const month = url.searchParams.get("month") ?? "";
  const from = url.searchParams.get("from") ?? "";
  const to = url.searchParams.get("to") ?? "";

  if (!["utilization", "payments", "bookings"].includes(report)) {
    return respond(400, "BAD_REQUEST", "Unknown report");
  }

  const serviceClient = deps?.getServiceClient
    ? deps.getServiceClient()
    : makeServiceClient(
        Deno.env.get("SUPABASE_URL"),
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
      );

  const viewMap: Record<string, string> = {
    utilization: "v_analytics_utilization",
    payments: "v_analytics_payments",
    bookings: "v_analytics_bookings",
  };
  let query = serviceClient.from(viewMap[report]).select("*");
  if (month) query = query.eq("month", month);
  if (from) query = query.gte("month", from);
  if (to) query = query.lte("month", to);

  const { data, error: qErr } = await query;
  if (qErr) {
    console.error("analytics-export query error", qErr);
    return respond(500, "INTERNAL", "Export failed");
  }

  const rows = (data ?? []).map((r: Record<string, unknown>) =>
    Object.values(r).map(String),
  );
  const headers = data && data.length > 0 ? Object.keys(data[0]) : ["empty"];

  return new Response(buildCsv(headers, rows), {
    headers: {
      ...corsHeaders,
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="${report}-${month}.csv"`,
    },
  });
}

if (import.meta.main && typeof Deno !== "undefined" && Deno.serve) {
  Deno.serve((req) =>
    handleRequest(req, {
      getServiceClient: () =>
        makeServiceClient(
          Deno.env.get("SUPABASE_URL"),
          Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
        ),
      getUserClient: (token: string) =>
        createClient(
          Deno.env.get("SUPABASE_URL")!,
          Deno.env.get("SUPABASE_ANON_KEY")!,
          { global: { headers: { Authorization: `Bearer ${token}` } } },
        ),
      getUser: async (token) =>
        createClient(
          Deno.env.get("SUPABASE_URL")!,
          Deno.env.get("SUPABASE_ANON_KEY")!,
          { global: { headers: { Authorization: `Bearer ${token}` } } },
        ).auth.getUser(token),
    }),
  );
}
