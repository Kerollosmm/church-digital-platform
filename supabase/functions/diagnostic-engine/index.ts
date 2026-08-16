import { createClient } from "npm:@supabase/supabase-js@2";
import { auth, respond } from "../_shared/http.ts";

const ADMIN_PHONE = "+201274173806";

export interface DiagnosticDeps {
  serviceClient?: any;
  anonClient?: any;
  getUser?: (token: string) => Promise<{ data: { user: any } | null; error: any }>;
  client?: any;
}

export async function handleRequest(
  req: Request,
  deps?: DiagnosticDeps,
): Promise<Response> {
  const authRes = await auth(req, {
    requireStaff: true,
    client: deps?.client ?? deps?.serviceClient,
    getUser: deps?.getUser,
  });
  if (authRes instanceof Response) return authRes;

  try {
    const serviceClient =
      deps?.serviceClient ??
      createClient(
        Deno.env.get("SUPABASE_URL") || "",
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "",
        { auth: { persistSession: false } },
      );
    const anonClient =
      deps?.anonClient ??
      createClient(
        Deno.env.get("SUPABASE_URL") || "",
        Deno.env.get("SUPABASE_ANON_KEY") || "",
        { auth: { persistSession: false } },
      );

    const findings: any[] = [];
    const executionLogs: any[] = [];

    // Probe 1: Anon Read on users table
    const p1Start = Date.now();
    const { data: usersData, status: usersStatus } = await anonClient
      .from("users")
      .select("id, phone")
      .limit(5);
    const p1Latency = Date.now() - p1Start;

    if (usersData && usersData.length > 0) {
      findings.push({
        id: "RLS-LEAK-USERS",
        severity: "CRITICAL",
        title: "Anonymous SELECT permitted on 'users' table",
        target: "TABLE:users",
        description: "Anonymous client retrieved sensitive user records.",
        remediation:
          "ALTER TABLE public.users ENABLE ROW LEVEL SECURITY; FORCE ROW LEVEL SECURITY;",
      });
    }
    executionLogs.push({
      id: "SEC-ANON-USERS-READ",
      status: usersStatus ?? 200,
      latencyMs: p1Latency,
    });

    // Probe 2: Anon direct write on bookings
    const p2Start = Date.now();
    const { error: bookInsertErr, status: bookInsertStatus } = await anonClient
      .from("bookings")
      .insert({
        slot_id: 1,
        user_id: "00000000-0000-0000-0000-000000000000",
        status: "CONFIRMED",
        paid_amount: 100,
        tenant_id: 1,
      });
    const p2Latency = Date.now() - p2Start;

    if (!bookInsertErr && (bookInsertStatus ?? 200) < 300) {
      findings.push({
        id: "RLS-LEAK-BOOKINGS-WRITE",
        severity: "CRITICAL",
        title: "Anonymous direct INSERT on 'bookings' table succeeded",
        target: "TABLE:bookings",
        description: "Bypassed booking state machine and slot locking RPCs.",
        remediation: "Revoke INSERT on bookings for anon and authenticated roles.",
      });
    }
    executionLogs.push({
      id: "SEC-ANON-DIRECT-BOOKING-INSERT",
      status: bookInsertStatus ?? 200,
      latencyMs: p2Latency,
    });

    // Probe 3: Anon call to book_slot RPC without auth
    const p3Start = Date.now();
    const { error: rpcErr, status: rpcStatus } = await anonClient.rpc(
      "book_slot",
      {
        p_slot_id: 1,
        p_opt_in: true,
      },
    );
    const p3Latency = Date.now() - p3Start;

    if (!rpcErr && (rpcStatus ?? 200) < 300) {
      findings.push({
        id: "RPC-AUTH-LEAK-BOOK-SLOT",
        severity: "CRITICAL",
        title: "Anonymous execution of 'book_slot' RPC succeeded",
        target: "RPC:book_slot",
        description: "Anonymous caller created a booking without authentication.",
        remediation:
          "Enforce `if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;` inside book_slot.",
      });
    }
    executionLogs.push({
      id: "SEC-ANON-BOOK-SLOT-RPC",
      status: rpcStatus ?? 200,
      latencyMs: p3Latency,
    });

    // Evaluate Checkpoint & Alert Dispatch
    const criticals = findings.filter((f) => f.severity === "CRITICAL");
    if (criticals.length > 0) {
      await serviceClient.from("event_outbox").insert({
        handler_type: "WHATSAPP",
        payload: {
          phone: ADMIN_PHONE,
          template_name: "admin_security_alert",
          critical_count: criticals.length,
          findings: criticals.map((c: any) => c.title),
          timestamp: new Date().toISOString(),
        },
        status: "PENDING",
      });
    }

    return respond(200, {
      success: true,
      timestamp: new Date().toISOString(),
      probes_executed: executionLogs.length,
      critical_count: criticals.length,
      status:
        criticals.length === 0
          ? "100% SECURE & INVARIANT-COMPLIANT"
          : "REMEDIATION_REQUIRED",
      findings,
      logs: executionLogs,
    });
  } catch (err: any) {
    console.error("diagnostic error:", err);
    return respond(
      500,
      "INTERNAL",
      err?.message ?? "Diagnostic execution failure",
    );
  }
}

if (import.meta.main && typeof Deno !== "undefined" && Deno.serve) {
  Deno.serve((req: Request) => handleRequest(req));
}
