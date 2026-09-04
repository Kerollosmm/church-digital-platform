# Event-Dispatcher Handler Throw Isolation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Isolate per-row handler failures in the event-dispatcher batch loop so one network throw can no longer orphan an entire batch's status writes (duplicate WhatsApp/FCM sends via the 5-minute reaper), and lock the mixed-batch split-write logic in with a regression test.

**Architecture:** The dispatcher claims PENDING outbox rows via `claim_event_outbox_batch`, marks them PROCESSING, then runs all handlers in a batch concurrently with `Promise.all`. Today a handler that *throws* (network exception in `sendWhatsApp`'s or `sendFcmPush`'s `deps.fetch`) rejects the whole `Promise.all`, so no status writes run: every row stays PROCESSING until `reap_stuck_outbox_events` (pg_cron, every 5 min, migration 0053) resets them to PENDING — re-sending messages that already went out. Fix: catch throws per row inside the map callback and convert them to the existing retryable `Result` shape; the deferred bulk-SENT + individual non-SENT status writes then always run.

**Tech Stack:** Deno edge function (TypeScript), `jsr:@std/assert` + `jsr:@std/testing/mock` tests, in-memory `FakeClient`/`FakeQuery` test double from `supabase/functions/_shared/fake_supabase.ts`.

**Spec:** 2026-09-04 two-axis code review of the uncommitted working tree (this session) — Standards Finding 1 (HIGH) and Spec Findings 1–2 (MEDIUM). Backing invariants: `memory-bank/systemPatterns.md` §5 Transactional Outbox, `AGENTS.md` "State RPCs & Outbox".

## Global Constraints

- Executor does NOT run `git add` / `git commit` — the orchestrator commits after re-running gates. Commit steps below are orchestrator steps.
- Touch ONLY: `supabase/functions/event-dispatcher/index.ts` and `supabase/functions/event-dispatcher/index_test.ts`.
- Zero-Leak Error Contract (`AGENTS.md`): handler errors must never reach the HTTP response body; the response stays `respond(200, { ok: true, handled })` on isolated failures. `console.error` server-side logging is allowed.
- No new deps, no new exports, no changes to `HANDLERS`, `TEMPLATES`, `claim_event_outbox_batch`, or the reaper.
- Test command (exact): `deno test --allow-env --allow-net supabase/functions/event-dispatcher/`
- Full-suite gate (exact): `deno test --allow-env --allow-net supabase/functions/`
- `type Result = { ok: boolean; retryable: boolean; error?: string }` (index.ts:45, not exported — same-file use only). Constants: `MAX_ATTEMPTS = 5`, `BACKOFF_MS = 30_000`, `DRAIN_BATCH = 10`, `DRAIN_LIMIT = 100` (index.ts:21-24).

---

### Task 0: Commit existing verified working-tree batch (orchestrator only — SKIP if executor)

The working tree holds a verified 17-file batch (CLEAN-06..16, SEC-OTP-PII, OPT-02/03; all gates green: `flutter analyze` 0 issues, mobile 88/88, admin 80/80, dispatcher deno 6/6). Commit it first so this fix lands as an isolated, reviewable commit.

- [ ] **Step 0.1: Commit the 17 modified files**

```bash
git add apps/admin/lib/features/auth/otp_screen.dart apps/mobile/lib/core/auth/phone_verify_gate.dart apps/mobile/lib/features/auth/login_screen.dart apps/mobile/lib/features/auth/otp_screen.dart apps/mobile/lib/features/booking/booking_detail_screen.dart apps/mobile/lib/features/family_archive/family_certificates_screen.dart diagnostic_engine/deno_engine.ts diagnostic_engine/engine.ts diagnostic_engine/test_real_all_features.ts diagnostic_engine/test_real_analytics_export.ts diagnostic_engine/test_real_event_dispatcher.ts diagnostic_engine/test_real_high_concurrency.ts memory-bank/activeContext.md memory-bank/progress.md scripts/test-sql.js supabase/functions/event-dispatcher/index.ts test-apps/superadmin/app.js
git commit -m "refactor(clients): decompose build methods, redact OTP PII, bulk outbox status writes (CLEAN-06..16, SEC-OTP-PII, OPT-02/03)"
```

---

### Task 1: Per-row handler throw isolation (TDD)

**Files:**
- Modify: `supabase/functions/event-dispatcher/index.ts:309-334` (the `batch.map` callback body)
- Test: `supabase/functions/event-dispatcher/index_test.ts` (append new test at end of file)

**Interfaces:**
- Consumes: existing `Result` type (index.ts:45), `HANDLERS` map (index.ts:263), `Row` type (index.ts:39), test helpers `jsonRes`/`authedReq`/`DEFAULT_DEPS` (index_test.ts:6-20), `FakeClient` (fake_supabase.ts:121).
- Produces: unchanged `handleRequest(req, deps): Promise<Response>` behavior for non-throwing handlers; new behavior — a throwing handler yields HTTP 200 with its row marked `PENDING`, `attempts + 1`, `last_error` = thrown message.

- [ ] **Step 1.1: Write the failing test**

Append to `supabase/functions/event-dispatcher/index_test.ts`:

```ts
Deno.test("event-dispatcher: WHATSAPP network throw is isolated and marked retryable", async () => {
  const fake = new FakeClient(["event_outbox", "whatsapp_optins"]);
  fake.seed("whatsapp_optins", [
    { phone: "+201000000009" },
  ]);
  fake.seed("event_outbox", [
    {
      id: 50,
      handler_type: "WHATSAPP",
      payload: {
        phone: "+201000000009",
        template_name: "booking_confirmed",
        params: { booking_id: 77 },
      },
      status: "PENDING",
      attempts: 0,
      next_attempt_at: "2026-08-05T00:00:00Z",
    },
  ]);

  const fetchStub = stub(globalThis, "fetch", () =>
    Promise.reject(new Error("Simulated network failure"))
  );

  try {
    const res = await handleRequest(authedReq(), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      ...DEFAULT_DEPS,
      whatsappToken: "mock-wa-token",
    });

    assertEquals(res.status, 200);
    const body = await res.json();
    assertEquals(body, { ok: true, handled: 0 });

    const row = fake.tableRows("event_outbox")[0];
    assertEquals(row.status, "PENDING");
    assertEquals(row.attempts, 1);
    assertEquals(row.last_error, "Simulated network failure");
  } finally {
    fetchStub.restore();
  }
});
```

- [ ] **Step 1.2: Run test to verify it fails**

Run: `deno test --allow-env --allow-net supabase/functions/event-dispatcher/`
Expected: the new test FAILS at `assertEquals(res.status, 200)` — actual 500, because the fetch rejection propagates out of `Promise.all` into the outer `catch` returning `respond(500, "INTERNAL")` (index.ts:377-380). All 6 existing tests still pass.

- [ ] **Step 1.3: Implement the fix**

In `supabase/functions/event-dispatcher/index.ts`, inside `handleRequest`'s `batch.map(async (row) => {` callback, find (around line 315):

```ts
          const outcome = await handler(row as Row, deps);
```

Replace with:

```ts
          let outcome: Result;
          try {
            outcome = await handler(row as Row, deps);
          } catch (err) {
            outcome = {
              ok: false,
              retryable: true,
              error: err instanceof Error ? err.message : "Handler threw",
            };
          }
```

This sits after the existing unknown-handler guard (which returns a FAILED outcome object) and before the `if (outcome.ok)` branch — no other lines change. The existing retryable path then applies the standard backoff: `PENDING`, `attempts + 1`, `next_attempt_at = now + 30s * 2^attempts`, `last_error` = thrown message; `attempts >= 5` becomes FAILED.

- [ ] **Step 1.4: Run tests to verify they pass**

Run: `deno test --allow-env --allow-net supabase/functions/event-dispatcher/`
Expected: 7 passed, 0 failed (6 existing + 1 new).

- [ ] **Step 1.5: Run full edge-function suite**

Run: `deno test --allow-env --allow-net supabase/functions/`
Expected: all pass (73 + 1 new = 74 or higher, depending on suite state).

- [ ] **Step 1.6: Commit (orchestrator only)**

```bash
git add supabase/functions/event-dispatcher/index.ts supabase/functions/event-dispatcher/index_test.ts
git commit -m "fix(outbox): isolate per-row handler throws in event-dispatcher batch loop"
```

---

### Task 2: Mixed-batch split-write regression test

**Files:**
- Test: `supabase/functions/event-dispatcher/index_test.ts` (append new test at end of file)
- No production code changes.

**Interfaces:**
- Consumes: Task 1's throw-isolation behavior; existing split-write logic (bulk `setStatus(client, sentIds, "SENT", { last_error: null })` then individual `Promise.all` over non-SENT outcomes); `DRAIN_BATCH = 10` so 3 seeded rows form exactly one batch.
- Produces: regression lock only — no new runtime surface.

- [ ] **Step 2.1: Write the test**

Append to `supabase/functions/event-dispatcher/index_test.ts`:

```ts
Deno.test("event-dispatcher: mixed batch splits status writes (SENT bulk, FAILED and PENDING individual)", async () => {
  const fake = new FakeClient(["event_outbox", "whatsapp_optins"]);
  fake.seed("whatsapp_optins", [
    { phone: "+201000000001" },
    { phone: "+201000000003" },
  ]);
  fake.seed("event_outbox", [
    {
      id: 40,
      handler_type: "WHATSAPP",
      payload: { phone: "+201000000001", template_name: "booking_confirmed", params: { booking_id: 1 } },
      status: "PENDING",
      attempts: 0,
      next_attempt_at: "2026-08-05T00:00:00Z",
    },
    {
      id: 41,
      handler_type: "WHATSAPP",
      payload: { phone: "+201000000002", template_name: "booking_confirmed", params: { booking_id: 2 } },
      status: "PENDING",
      attempts: 0,
      next_attempt_at: "2026-08-05T00:00:00Z",
    },
    {
      id: 42,
      handler_type: "WHATSAPP",
      payload: { phone: "+201000000003", template_name: "booking_confirmed", params: { booking_id: 3 } },
      status: "PENDING",
      attempts: 0,
      next_attempt_at: "2026-08-05T00:00:00Z",
    },
  ]);

  const fetchStub = stub(globalThis, "fetch", (_url: RequestInfo | URL, init?: RequestInit) => {
    const to = (JSON.parse(String(init?.body ?? "{}")) as { to?: string }).to;
    if (to === "+201000000003") {
      return Promise.reject(new Error("Simulated network failure"));
    }
    return Promise.resolve(jsonRes({ messages: [{ id: "wamid.mix" }] }));
  });

  try {
    const res = await handleRequest(authedReq(), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub,
      ...DEFAULT_DEPS,
      whatsappToken: "mock-wa-token",
    });

    assertEquals(res.status, 200);
    const body = await res.json();
    assertEquals(body, { ok: true, handled: 1 });

    const rows = fake.tableRows("event_outbox");
    const byId = new Map(rows.map((r) => [r.id, r]));
    assertEquals(byId.get(40)?.status, "SENT");
    assertEquals(byId.get(40)?.last_error, null);
    assertEquals(byId.get(41)?.status, "FAILED");
    assertEquals(byId.get(41)?.last_error, "No WhatsApp opt-in found");
    assertEquals(byId.get(42)?.status, "PENDING");
    assertEquals(byId.get(42)?.attempts, 1);
    assertEquals(byId.get(42)?.last_error, "Simulated network failure");
  } finally {
    fetchStub.restore();
  }
});
```

Row design: id 40 has an opt-in and a successful fetch → SENT via the bulk `.in("id", sentIds)` write with `last_error: null`. Id 41 has NO opt-in row, so `sendWhatsApp` returns non-retryable FAILED with `"No WhatsApp opt-in found"` before ever calling fetch. Id 42 has an opt-in but its fetch rejects → Task 1's catch → retryable → PENDING, attempts 1, backoff scheduled. `handled` counts only SENT → 1.

- [ ] **Step 2.2: Run tests**

Run: `deno test --allow-env --allow-net supabase/functions/event-dispatcher/`
Expected: 8 passed, 0 failed. This test is a characterization/regression lock — it should PASS immediately after Task 1. If it FAILS, that reveals a real bug in the split-write logic: STOP, capture the assertion diff, report it; do not weaken assertions to force green.

- [ ] **Step 2.3: Run full edge-function suite**

Run: `deno test --allow-env --allow-net supabase/functions/`
Expected: all pass.

- [ ] **Step 2.4: Commit (orchestrator only)**

```bash
git add supabase/functions/event-dispatcher/index_test.ts
git commit -m "test(outbox): mixed-batch split-write regression coverage for event-dispatcher"
```

---

## Self-Review

1. **Spec coverage:** Review Standards Finding 1 (unguarded handler throw) → Task 1. Review Spec Finding 1 (non-atomic split writes amplification) → Task 1 removes the routine trigger; residual setStatus-failure path recovers via reaper — documented, out of scope. Review Spec Finding 2 (no mixed-batch test) → Task 2. LOW smell findings (shared auth widgets, 202-line dialog, `dynamic price`, parallel arrays) intentionally out of scope — optional follow-ups.
2. **Placeholder scan:** No TBD/TODO/vague steps; every code step carries the full code.
3. **Type consistency:** `Result` shape `{ ok, retryable, error? }` matches index.ts:45; test rows use the exact seed shape of existing tests (index_test.ts:45-58); `handled: 1` matches the reduce over `outcome.handled` where only SENT yields 1; `last_error` values match the literal strings in index.ts (`"No WhatsApp opt-in found"` at line 76, thrown message passthrough in Task 1's catch).
