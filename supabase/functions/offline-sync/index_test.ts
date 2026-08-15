import { assertEquals } from "jsr:@std/assert";
import { handleRequest } from "./index.ts";
import { FakeClient } from "../_shared/fake_supabase.ts";

Deno.test("offline-sync: rejects non-array mutations with HTTP 400", async () => {
  const req = new Request("https://x/functions/v1/offline-sync", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ mutations: "invalid" }),
  });
  const res = await handleRequest(req, {
    getClient: () => new FakeClient([]),
  });
  assertEquals(res.status, 400);
  const json = await res.json();
  assertEquals(json.error, "Invalid payload. 'mutations' must be an array.");
});

Deno.test("offline-sync: handles CORS preflight OPTIONS with HTTP 200", async () => {
  const req = new Request("https://x/functions/v1/offline-sync", {
    method: "OPTIONS",
  });
  const res = await handleRequest(req);
  assertEquals(res.status, 200);
});

Deno.test("offline-sync: successfully passes mutations array to sync_offline_mutations RPC", async () => {
  let rpcCalled = false;
  let receivedMutations: unknown = null;

  const fakeClient = {
    rpc: (name: string, args: Record<string, unknown>) => {
      if (name === "sync_offline_mutations") {
        rpcCalled = true;
        receivedMutations = args.p_mutations;
        return Promise.resolve({
          data: { processed: 2, conflicts: 0, server_time: new Date().toISOString() },
          error: null,
        });
      }
      return Promise.resolve({ data: null, error: { message: "Unknown RPC" } });
    },
  };

  const sampleMutations = [
    { client_id: "mut-1", table: "attendance", op: "INSERT", data: { member_id: "m-1", attended: true } },
    { client_id: "mut-2", table: "attendance", op: "INSERT", data: { member_id: "m-2", attended: true } },
  ];

  const req = new Request("https://x/functions/v1/offline-sync", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: "Bearer test-jwt-token",
    },
    body: JSON.stringify({ mutations: sampleMutations }),
  });

  const res = await handleRequest(req, {
    getClient: () => fakeClient as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
  });

  assertEquals(res.status, 200);
  assertEquals(rpcCalled, true);
  assertEquals(receivedMutations, sampleMutations);
  const json = await res.json();
  assertEquals(json.success, true);
  assertEquals(json.result.processed, 2);
});
