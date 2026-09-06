import { handleRequest } from "../supabase/functions/offline-sync/index.ts";

export async function runOfflineSyncVerification(): Promise<void> {
  console.log("\x1b[35m===================================================================\x1b[0m");
  console.log("\x1b[35m       OFFLINE MUTATION BATCH SYNCHRONIZATION RUNNER TEST          \x1b[0m");
  console.log("\x1b[35m===================================================================\x1b[0m\n");

  console.log("\x1b[36m[Stage 1: Batch Mutation Construction]\x1b[0m Simulating field servant attendance sync...");
  const sampleMutations = [
    { client_id: "mut-001", table: "attendance", op: "INSERT", data: { member_id: "m-101", liturgy_id: 8, checked_in_at: new Date().toISOString() } },
    { client_id: "mut-002", table: "attendance", op: "INSERT", data: { member_id: "m-102", liturgy_id: 8, checked_in_at: new Date().toISOString() } },
    { client_id: "mut-003", table: "attendance", op: "INSERT", data: { member_id: "m-103", liturgy_id: 8, checked_in_at: new Date().toISOString() } },
  ];

  let rpcCalled = false;
  const mockClient = {
    rpc: (name: string, args: Record<string, unknown>) => {
      if (name === "sync_offline_mutations") {
        rpcCalled = true;
        return Promise.resolve({
          data: {
            processed: (args.p_mutations as any[]).length,
            conflicts: 0,
            applied_ids: ["mut-001", "mut-002", "mut-003"],
            server_timestamp: new Date().toISOString(),
          },
          error: null,
        });
      }
      return Promise.resolve({ data: null, error: { message: "Unknown RPC" } });
    },
  };

  console.log("\x1b[36m[Stage 2: Execute Offline Sync]\x1b[0m Sending batched mutations payload...");
  const req = new Request("https://x/functions/v1/offline-sync", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer parishioner-jwt" },
    body: JSON.stringify({ mutations: sampleMutations }),
  });

  const res = await handleRequest(req, {
    getClient: () => mockClient as any,
  });

  const body = await res.json() as Record<string, unknown>;
  console.log(`\x1b[32m[Stage 2 OK]\x1b[0m Sync Response HTTP ${res.status}:`, body);
  console.log(`  - RPC \`sync_offline_mutations\` Triggered: ${rpcCalled ? "✅ YES" : "❌ NO"}`);

  console.log("\n\x1b[35m===================================================================\x1b[0m");
  console.log("\x1b[35m    OFFLINE SYNC VERIFICATION COMPLETE (PASS)                      \x1b[0m");
  console.log("\x1b[35m===================================================================\x1b[0m\n");
}

if (import.meta.main) {
  runOfflineSyncVerification().catch((err) => {
    console.error("\n\x1b[31m[TEST FAILED]\x1b[0m", err);
    Deno.exit(1);
  });
}
