import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

export interface OfflineSyncDeps {
  getClient?: (authHeader?: string | null) => unknown;
}

export async function handleRequest(req: Request, deps?: OfflineSyncDeps): Promise<Response> {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    let supabase: SupabaseClient;

    if (deps?.getClient) {
      supabase = deps.getClient(authHeader) as unknown as SupabaseClient;
    } else {
      const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
      const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

      if (!supabaseUrl || !supabaseAnonKey) {
        throw new Error("Missing SUPABASE_URL or SUPABASE_ANON_KEY environment variables.");
      }

      // Initialize Supabase Client with caller's JWT auth context
      supabase = createClient(supabaseUrl, supabaseAnonKey, {
        global: { headers: { Authorization: authHeader ?? "" } },
      });
    }

    const body = await req.json().catch(() => ({}));
    const { mutations } = body;

    if (!Array.isArray(mutations)) {
      return new Response(
        JSON.stringify({ error: "Invalid payload. 'mutations' must be an array." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Invoke SECURITY DEFINER RPC for offline batch sync
    const { data, error } = await supabase.rpc("sync_offline_mutations", {
      p_mutations: mutations,
    });

    if (error) {
      console.error("sync_offline_mutations RPC error:", error);
      return new Response(
        JSON.stringify({ error: "Sync failed" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({ success: true, result: data }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("offline-sync edge function failure:", err);
    return new Response(
      JSON.stringify({ error: "Internal Server Error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
}

if (import.meta.main) {
  Deno.serve((req: Request) => handleRequest(req));
}
