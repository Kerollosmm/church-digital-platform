# Session Handoff Document — Church Digital Platform Implementation

**Date:** 2026-08-11  
**Project:** Church Digital Platform (`C:\church`)  
**Status:** Tasks 1–5 Complete & Approved by Senior Dev B (OpenCode DeepSeek V4). Next up: **Task 6**.

---

## 1. Project Context & Source of Truth

- **Master Implementation Plan**: [`docs/superpowers/plans/2026-08-10-church-digital-platform-master-plan.md`](file:///C:/church/docs/superpowers/plans/2026-08-10-church-digital-platform-master-plan.md) (10 tasks total).
- **Backend & DB Conventions**: [`docs/superpowers/plans/conventions.md`](file:///C:/church/docs/superpowers/plans/conventions.md) (SECURITY DEFINER RPCs, RLS, slot locking, event outbox).
- **Monorepo Structure**:
  - Backend: [`supabase/migrations/`](file:///C:/church/supabase/migrations/) (0001–0031), [`supabase/functions/`](file:///C:/church/supabase/functions/) (Deno Edge Functions).
  - Parishioner Mobile: [`apps/mobile/`](file:///C:/church/apps/mobile/) (Flutter Mobile, Riverpod, GoRouter).
  - Admin Web Dashboard: [`apps/admin/`](file:///C:/church/apps/admin/) (Flutter Web PWA, Riverpod, GoRouter, `fl_chart`).

---

## 2. Agreed Workflow Protocol (Strictly Followed)

For every task in the plan:
1. **Subagent TDD Implementation**: Dispatch an implementer subagent to execute TDD (Step 1 write failing test → Step 2 verify FAIL → Step 3 write minimal implementation → Step 4 verify PASS → Step 5 git commit).
2. **Peer Review via OpenCode DeepSeek V4**: Run `node .agents/skills/opencode-delegate/scripts/relay.mjs --brief <brief_path> --model opencode/deepseek-v4-flash-free --read-only --cd C:\church`.
3. **Approval Gate**: Do NOT start the next task until OpenCode DeepSeek V4 returns explicit 100% approval/sign-off on the previous task.

---

## 3. Progress Scorecard & Completed Tasks (5/10 Tasks Finished)

| Task | Title & Deliverables | Commits | Test Suite Status | OpenCode Review Status |
| :--- | :--- | :--- | :--- | :--- |
| **Task 1** | FCM v1 Handler + Migration 0029 | `273c8f7`, `926adef` | 13/13 Deno tests PASS | **100% Approved** |
| **Task 2** | CSV Export Sanitization & Date Filters | `6808575b` | 12/12 Deno tests PASS | **100% Approved** |
| **Task 3** | Admin Web App Auth & Role Access Control | `e519101`, `f24ee1e` | 4/4 Flutter tests PASS | **100% Approved** |
| **Task 4** | Admin Shell Navigation & GoRouter Shell | `01ee03d` | 20/20 Flutter tests PASS | **100% Approved** |
| **Task 5** | Realtime Bookings & Slots Monitor + 0031 | `f40d04b1` | 21/21 Flutter tests PASS | **100% Approved** |
| **Task 6** | Manual Booking & Emergency Override Screens | *Pending* | *Pending* | *Pending* |
| **Task 7** | Complaints Inbox & PGP RPC Decryption | *Pending* | *Pending* | *Pending* |
| **Task 8** | Attendance & Capacity Chart Widgets | *Pending* | *Pending* | *Pending* |
| **Task 9** | Revenue & Payment Breakdown Dashboard | *Pending* | *Pending* | *Pending* |
| **Task 10** | Release Gate & Source-of-Truth Sync | *Pending* | *Pending* | *Pending* |

---

## 4. Next Immediate Steps for Fresh Agent

1. **Start Task 6**: Manual Booking & Emergency Override Screens in `apps/admin`.
   - **Target Files**:
     - `apps/admin/lib/features/bookings/manual_book_screen.dart`
     - `apps/admin/lib/features/bookings/emergency_override_screen.dart`
     - `apps/admin/test/features/bookings/manual_book_screen_test.dart`
     - `apps/admin/test/features/bookings/emergency_override_screen_test.dart`
   - **RPCs Used**: `manual_book(p_slot_id, p_phone, p_opt_in, p_notes)` and `emergency_override(p_booking_id, p_new_slot_id, p_refund)`.
2. **Review Loop**: Relay Task 6 diff to OpenCode DeepSeek V4 via `opencode-delegate` script (`relay.mjs --read-only`).
3. **Continue Tasks 7–10** until the plan is 100% complete.

---

## 5. Suggested Skills

- `using-superpowers`
- `subagent-driven-development`
- `opencode-delegate`
- `flutter-apply-architecture-best-practices`
- `clean-code-guard`
- `typescript-expert`
