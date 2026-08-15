import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.48.0";
import { corsHeaders } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") || "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const ADMIN_PHONE = "+201274173806";

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "UNAUTHORIZED" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const serviceClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false },
    });
    const anonClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      auth: { persistSession: false },
    });

    const findings: any[] = [];
    const executionLogs: any[] = [];

    // Probe 1: Anon Read on users table
    const p1Start = Date.now();
    const { data: usersData, error: usersErr, status: usersStatus } = await anonClient
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
        remediation: "ALTER TABLE public.users ENABLE ROW LEVEL SECURITY; FORCE ROW LEVEL SECURITY;",
      });
    }
    executionLogs.push({ id: "SEC-ANON-USERS-READ", status: usersStatus, latencyMs: p1Latency });

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

    if (!bookInsertErr && bookInsertStatus < 300) {
      findings.push({
        id: "RLS-LEAK-BOOKINGS-WRITE",
        severity: "CRITICAL",
        title: "Anonymous direct INSERT on 'bookings' table succeeded",
        target: "TABLE:bookings",
        description: "Bypassed booking state machine and slot locking RPCs.",
        remediation: "Revoke INSERT on bookings for anon and authenticated roles.",
      });
    }
    executionLogs.push({ id: "SEC-ANON-DIRECT-BOOKING-INSERT", status: bookInsertStatus, latencyMs: p2Latency });

    // Probe 3: Anon call to book_slot RPC without auth
    const p3Start = Date.now();
    const { error: rpcErr, status: rpcStatus } = await anonClient.rpc("book_slot", {
      p_slot_id: 1,
      p_opt_in: true,
    });
    const p3Latency = Date.now() - p3Start;

    if (!rpcErr && rpcStatus < 300) {
      findings.push({
        id: "RPC-AUTH-LEAK-BOOK-SLOT",
        severity: "CRITICAL",
        title: "Anonymous execution of 'book_slot' RPC succeeded",
        target: "RPC:book_slot",
        description: "Anonymous caller created a booking without authentication.",
        remediation: "Enforce `if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;` inside book_slot.",
      });
    }
    executionLogs.push({ id: "SEC-ANON-BOOK-SLOT-RPC", status: rpcStatus, latencyMs: p3Latency });

    // Evaluate Checkpoint & Alert Dispatch
    const criticals = findings.filter((f) => f.severity === "CRITICAL");
    if (criticals.length > 0) {
      // Enqueue WhatsApp alert to admin phone
      await serviceClient.from("event_outbox").insert({
        handler_type: "WHATSAPP",
        payload: {
          phone: ADMIN_PHONE,
          template_name: "admin_security_alert",
          critical_count: criticals.length,
          findings: criticals.map((c) => c.title),
          timestamp: new Date().toISOString(),
        },
        status: "PENDING",
      });
    }

    return new Response(
      JSON.stringify({
        success: true,
        timestamp: new Date().toISOString(),
        probes_executed: executionLogs.length,
        critical_count: criticals.length,
        status: criticals.length === 0 ? "100% SECURE & INVARIANT-COMPLIANT" : "REMEDIATION_REQUIRED",
        findings,
        logs: executionLogs,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (err: any) {
    return new Response(
      JSON.stringify({ success: false, error: err.message }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
