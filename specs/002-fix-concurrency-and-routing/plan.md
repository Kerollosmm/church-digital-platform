# Implementation Plan: Comprehensive Platform Hardening & Bug Fixes

**Branch**: `002-fix-concurrency-and-routing` | **Date**: 2026-08-15 | **Spec**: [`specs/002-fix-concurrency-and-routing/spec.md`](file:///c:/church/specs/002-fix-concurrency-and-routing/spec.md)

---

## 1. Summary

Remediate all 11 critical and major defects identified during the full platform audit across database RPCs, Edge Functions, mobile, and admin web applications. Resolve the role collapse desynchronization (`USER` vs `PARISHIONER`), implement automatic slot capacity restoration on booking cancellation/expiry, fix Paymob webhook payload parsing, fix YouTube video ID regex extraction, ensure FCM string payload coercion, prevent outbox worker duplicate execution via atomic `FOR UPDATE SKIP LOCKED`, and patch Flutter type cast errors and admin RPC invocations.

---

## 2. Technical Context

- **Frontend Stacks**: Flutter 3.x / Dart (Web + Mobile), Riverpod 2.x, GoRouter 14.x, `fl_chart`.
- **Backend Stack**: PostgreSQL 16 on Supabase (`pgcrypto`, `btree_gist`, `pg_cron`, `pg_net`), Deno Edge Functions (TypeScript).
- **Audit Findings Remediated**:
  1. Role checks in `book_slot` and `purchase_video` synchronized to `'USER'`/`'ADMIN'`.
  2. Slot capacity restoration trigger on `bookings` (`CANCELLED`, `EXPIRED`, `REFUNDED`).
  3. Paymob webhook payload wrapper unnesting (`body.obj ?? body`).
  4. YouTube URL regex extraction for video ID.
  5. Event outbox atomic claim RPC (`claim_event_outbox_batch`).
  6. FCM v1 data payload string coercion.
  7. SMS OTP secret prefix preservation.
  8. pg_net cron URL normalization (`regexp_replace(url, '^https?://', '')`).
  9. Flutter `(json['paid_amount'] as num?)?.toInt() ?? 0` type cast fixes.
  10. Admin Flutter RPC calls using named argument `params:`.
  11. Admin Realtime subscription moved to broadcast channel.

---

## 3. Constitution & Architecture Quality Check

| Pillar / Rule | Status | Validation Strategy |
| :--- | :---: | :--- |
| **I. Atomic Concurrency Control** | 🟢 Pass | `fn_book_slot_atomic` conditional update + capacity restoration trigger. |
| **II. Outbox Worker Concurrency** | 🟢 Pass | `claim_event_outbox_batch` using `FOR UPDATE SKIP LOCKED`. |
| **III. Ultra-Performant Multi-Tenant RLS** | 🟢 Pass | Scalar InitPlan caching `(SELECT auth.uid())` and JWT claims. |
| **IV. Edge Function Robustness** | 🟢 Pass | Paymob HMAC unnesting, YouTube regex, and FCM string coercion. |
| **V. Flutter Type Safety & Routing** | 🟢 Pass | Safe `num.toInt()` casts and `params:` named argument RPC calls. |

---

## 4. Phase Breakdown

- **Phase 0 (Research)**: Documented in [`research.md`](file:///c:/church/specs/002-fix-concurrency-and-routing/research.md).
- **Phase 1 (Data Model & Contracts)**:
  - Database schema & migration: [`data-model.md`](file:///c:/church/specs/002-fix-concurrency-and-routing/data-model.md)
  - RPC contracts: [`contracts/rpc-contracts.md`](file:///c:/church/specs/002-fix-concurrency-and-routing/contracts/rpc-contracts.md)
  - Verification runbook: [`quickstart.md`](file:///c:/church/specs/002-fix-concurrency-and-routing/quickstart.md)
- **Phase 2 (Implementation Tasks)**: Generate via `/speckit-tasks` or execute directly.