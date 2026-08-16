import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { createClient } from "npm:@supabase/supabase-js@2";
import { auth, respond } from "../_shared/http.ts";

export interface OfflineSyncDeps {
  client?: unknown;
  getClient?: (authHeader?: string | null) => unknown;
  getUser?: (token: string) => Promise<{ data: { user: any } | null; error: any }>;
}

export async function handleRequest(
  req: Request,
  deps?: OfflineSyncDeps,
): Promise<Response> {
  const authRes = await auth(req, {
    client:
      deps?.client ??
      (deps?.getClient
        ? deps.getClient(req.headers.get("Authorization"))
        : undefined),
    getUser: deps?.getUser,
  });
  if (authRes instanceof Response) return authRes;

  try {
    const authHeader =
      req.headers.get("Authorization") ?? req.headers.get("authorization");
    let supabase: SupabaseClient;

    if (deps?.client) {
      supabase = deps.client as unknown as SupabaseClient;
    } else if (deps?.getClient) {
      supabase = deps.getClient(authHeader) as unknown as SupabaseClient;
    } else {
      const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
      const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

      if (!supabaseUrl || !supabaseAnonKey) {
        throw new Error(
          "Missing SUPABASE_URL or SUPABASE_ANON_KEY environment variables.",
        );
      }

      supabase = createClient(supabaseUrl, supabaseAnonKey, {
        global: { headers: { Authorization: authHeader ?? "" } },
      });
    }

    const body = await req.json().catch(() => ({}));
    const { mutations } = body;

    if (!Array.isArray(mutations)) {
      return respond(
        400,
        "BAD_REQUEST",
        "Invalid payload. 'mutations' must be an array.",
      );
    }

    const { data, error } = await supabase.rpc("sync_offline_mutations", {
      p_mutations: mutations,
    });

    if (error) {
      console.error("sync_offline_mutations RPC error:", error);
      return respond(500, "INTERNAL", "Sync failed");
    }

    return respond(200, { success: true, result: data });
  } catch (err) {
    console.error("offline-sync edge function failure:", err);
    return respond(500, "INTERNAL", "Internal Server Error");
  }
}

if (import.meta.main) {
  Deno.serve((req: Request) => handleRequest(req));
}
