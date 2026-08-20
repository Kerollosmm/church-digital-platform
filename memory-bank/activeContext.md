# Active Context: Church Digital Platform

## Current Focus & Status
- **Current Feature**: `009-schema-integrity-fixes` (**100% Implemented & Verified**).
  - All 53 SQL test suites passing over stdin via `npm run test:sql` (`node scripts/test-sql.js`) with 0 failures and verified TAP output.
  - All 84 Deno edge function unit tests passing (`deno test --allow-env --allow-net supabase/functions/`).
  - Forward migrations `0055` through `0062` applied cleanly.
  - Constitution bumped to version 1.1.0 with ADR 0002.
- **Next Immediate Step**: Review / commit Feature 009 branch and proceed to Feature 008 or next scheduled roadmap milestone.

## Key Accomplishments & Deliverables (Feature 009)
1. **Vault Preflight & Provisioning (US1 — `0055_vault_preflight.sql`)**:
   - Built `public.vault_preflight()` returning missing runtime secrets with zero secret disclosure.
   - Provisioned mock development secrets in `supabase/seed.sql` (`COMPLAINTS_KEY`, `SUPABASE_URL`, `SERVICE_ROLE_KEY`).
   - Documented operational procedures in `docs/ops/runbook.md` §5 & §6.
2. **Close Email Registration Path (US2 — `0056_harden_handle_new_user.sql`)**:
   - Enforced phone number requirement on `handle_new_user` trigger with `PHONE_REQUIRED` exception.
   - Disabled email signups in `supabase/config.toml` (`[auth.email] enable_signup = false`).
3. **Integrity Constraints & Enums (US3 — `0057_integrity_constraints.sql`, `0058_status_enums.sql`)**:
   - Added CHECK constraints on `service_slots.capacity > 0`, `service_slots.price >= 0`, `payments.amount > 0`, `media_assets` alt-text requirement, `event_outbox.status` enum membership, `event_outbox.attempts <= 5`.
   - Replaced free-form text with Postgres enums: `public.slot_status` (`'OPEN'`, `'CLOSED'`) and `public.waitlist_status` (`'WAITING'`, `'OFFERED'`).
   - Recreated dependent views `v_available_slots`, `v_schedule_today`, `v_services` with `security_invoker = true`.
4. **Tenant Scaffolding (US4 — `0059_tenant_scaffolding.sql`)**:
   - Primary key on `payments_monthly` set to `(tenant_id, month)`.
   - Analytics materialization function `materialize_analytics()` scoped by `tenant_id`.
   - `audit_log.tenant_id` and `whatsapp_optins.tenant_id` given `NOT NULL DEFAULT public.tenant_id()`.
   - `whatsapp_optins` primary key set to `(tenant_id, phone)` and RPCs `book_slot` and `manual_book` updated.
5. **Priest Abstraction Removal (US5 — `0060_remove_priest_abstraction.sql`)**:
   - Recreated 8 policies across `announcements`, `faq`, `faq_categories`, `priests`, `services`, `service_slots`, `slot_utilization_monthly`, `payments_monthly`, `bookings_monthly` to use `public.is_admin()`.
   - Updated `publish_announcement` and dropped `public.is_admin_or_priest()`.
   - Deleted obsolete `0005_priest_self_assign_test.sql`.
6. **User Deletion Semantics (US6 — `0061_user_delete_semantics.sql`)**:
   - Replaced implicit `NO ACTION` with explicit `ON DELETE RESTRICT` on foreign keys referencing `public.users` from `bookings`, `complaints`, and `waiting_list`.
7. **Constitution Realignment & Orphan Enum Drop (US7 — `0062_drop_video_privacy_enum.sql`)**:
   - Dropped orphan `public.video_privacy` enum type.
   - Authored `docs/adr/0002-video-to-event-booking-pivot.md`.
   - Amended `.specify/memory/constitution.md` to version 1.1.0 reflecting Event Booking with Extra Services product truth.
