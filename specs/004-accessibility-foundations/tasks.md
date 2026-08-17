---
description: "Task list for 004-accessibility-foundations implementation (post owner-interview 2026-08-17)"
---

# Tasks: 004-accessibility-foundations

**Input**: Design documents from `/specs/004-accessibility-foundations/` (plan.md, spec.md, research.md, data-model.md, contracts/publish-validation-and-messages.md, quickstart.md)

**Prerequisites**: feature 003 MERGED to main before starting. Repo TDD protocol mandatory: every test task runs RED before its implementation task, GREEN after.

**Organization**: grouped by user story — US1 alt text (P1, MVP), US2 personal video delivery (P2), US3 localized errors (P3).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: parallelizable (different files / independent)
- **[Story]**: US1 / US2 / US3 per spec.md

## Path Conventions

Repo-root layout: `supabase/migrations/`, `supabase/tests/`, `supabase/functions/` (see plan.md §Project Structure).

---

## Phase 1: Setup

- [X] T001 Verify prerequisites: `git log main` shows 003-edge-function-kernel merged; `git checkout main && git checkout -b 004-accessibility-foundations`; `npx supabase start && npx supabase db reset` green through 0048
- [X] T002 Create empty migration file `supabase/migrations/0049_accessibility_foundations.sql` (header comment only) so test tasks can reference it

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: shared schema both stories build on. Tests first.

- [X] T003 Write failing schema tests in `supabase/tests/0049_accessibility_test.sql` — section 1: `media_assets` + `error_messages` tables (columns per data-model.md, CHECK constraints, UNIQUE (bucket, storage_path, tenant_id), RLS enabled, tenant default, sequence grants); section 2: 6 seeded Arabic rows in `error_messages`. File uses `plan(...)`, BEGIN/ROLLBACK, explicit fixtures. Register `\ir 0049_accessibility_test.sql` in `supabase/tests/run_all.sql`
- [X] T004 Implement in `supabase/migrations/0049_accessibility_foundations.sql`: both tables (exact columns/constraints per data-model.md), `ALTER TABLE ... ENABLE ROW LEVEL SECURITY`, policies (media_assets: SELECT to anon, authenticated + tenant check; ALL-write to authenticated + is_admin() + tenant check; error_messages: SELECT to anon, authenticated + tenant; write is_admin()), `GRANT USAGE, SELECT ON SEQUENCE` for media_assets identity, seed 6 Arabic `error_messages` rows. Zero changes to any existing table. Run suite → section 1–2 GREEN

**Checkpoint**: tables + catalog exist; stories can proceed in parallel.

---

## Phase 3: User Story 1 — Blind parishioner hears what the images show (P1) — MVP

**Goal**: every published image has alt text or decorative flag; publish refuses without it; staff backlog lists offenders.
**Independent Test**: quickstart.md gates 1 (SQL) + 4 (backlog pagination probe).

### Tests (write FIRST, RED)

- [X] T005 [P] [US1] Failing tests in `supabase/tests/0049_accessibility_test.sql` section 3: media_assets behavior — non-decorative row with empty/whitespace `alt_text_ar` rejected; decorative row without alt accepted; Arabic text (with Coptic terms) stored and returned verbatim; anon can SELECT within tenant; non-admin INSERT denied (0 rows); admin INSERT accepted
- [X] T006 [P] [US1] Failing tests section 4: `publish_announcement` — refuses (`ALT_TEXT_REQUIRED`) when linked asset lacks alt/decorative and when announcement has images but zero linked assets; succeeds and sets `published_at` when all valid; `set_priest_photo` — refuses invalid asset (`INVALID_MEDIA_ASSET`), links valid one and updates `priests.photo_url`. Fixtures: announcements + priests + media_assets rows
- [X] T007 [P] [US1] Failing tests section 5: `get_backlog` keyset — ≥25 fixture offenders, pages of 10 via (created_at, id) cursor, union complete, no dupes; delete 5 mid-walk → remaining rows unchanged; `p_limit` capped at 100; anon/authenticated execution of `publish_announcement`, `set_priest_photo`, `get_backlog` denied (FR-011)

### Implementation

- [X] T008 [US1] Implement `publish_announcement(p_id)` + `set_priest_photo(p_priest_id, p_media_asset_id)` in `supabase/migrations/0049_accessibility_foundations.sql`: SECURITY DEFINER, `SET search_path = public, pg_temp`, internal role checks (is_admin_or_priest / is_admin), REVOKE ALL FROM PUBLIC, anon, authenticated → GRANT EXECUTE to authenticated. Single transaction, no partial effects
- [X] T009 [US1] Implement `v_content_backlog` (orphan priest photos + unlinked bucket objects; access revoked from anon/authenticated) + `get_backlog(p_before_created_at, p_after_id, p_limit)` RPC (service_role grant, admin check, keyset pagination) in same migration. Run suite → sections 3–5 GREEN

**Checkpoint**: US1 independently demoable via backlog RPC + publish refusal.

---

## Phase 4: User Story 2 — Booking holder receives his personal video automatically (P2)

**Goal**: staff enters phone + YouTube URL + title + PAID payment → unlisted video + access grant + one WhatsApp outbox event; idempotent; unknown phone refused.
**Independent Test**: SQL delivery tests + deno dispatcher test below.

### Tests (write FIRST, RED)

- [X] T010 [P] [US2] Failing tests in `supabase/tests/0049_accessibility_test.sql` section 6: `deliver_personal_video` — success creates videos row (UNLISTED, price 0, title verbatim) + video_purchases (access_granted_at set) + exactly one `event_outbox` row (template `video_ready`, payload carries video_id, purchase_id, buyer phone); `UNKNOWN_PHONE` refusal (no rows, no event); `PAYMENT_INVALID` (unpaid / wrong user) refusal; idempotent retry returns same video_id, no new rows/event; anon/authenticated execution denied
- [X] T011 [P] [US2] Failing deno test: `video_ready` template handler in `supabase/functions/event-dispatcher/index_test.ts` — fake client receives WhatsApp send with YouTube link; on success stamps `video_purchases.link_sent_at`

### Implementation

- [X] T012 [US2] Implement `deliver_personal_video(p_phone, p_yt_url, p_title_ar, p_payment_id)` in `supabase/migrations/0049_accessibility_foundations.sql` per data-model.md (exact users.phone match, PAID payment ownership, idempotency keyed on payment, SECURITY DEFINER + REVOKE → service_role). SQL section 6 GREEN
- [X] T013 [US2] Implement `video_ready` handler in `supabase/functions/event-dispatcher/index.ts` (send via existing drain path, stamp `link_sent_at` on success). Deno test GREEN

**Checkpoint**: end-to-end delivery (RPC → outbox → drain) demoable locally.

---

## Phase 5: User Story 3 — Elderly Arabic user meets errors in Arabic (P3)

**Goal**: every 4xx/5xx carries non-empty `message_ar`; rewording is data-level.
**Independent Test**: quickstart.md gate 3 (curl sweep) + deno cache tests.

### Tests (write FIRST, RED)

- [X] T014 [P] [US3] Failing deno tests in `supabase/functions/_tests/messages_test.ts`: `messageFor()` returns catalog Arabic for all 5 codes; cache hit within TTL (1 fetch, many calls, fake clock); reload after TTL expiry; lookup failure ⇒ FALLBACK Arabic sentence
- [X] T015 [P] [US3] Failing deno tests: extend `supabase/functions/_tests/http_test.ts` — every 4xx/5xx `respond()` body contains non-empty `message_ar`; unknown code ⇒ FALLBACK

### Implementation

- [X] T016 [US3] Implement `supabase/functions/_shared/messages.ts` (catalog load via service client, module-level cache, 5-min TTL, `messageFor(code)` fail-safe)
- [X] T017 [US3] Extend `supabase/functions/_shared/http.ts` `respond()` to include `message_ar` from `messageFor()` on 4xx/5xx. Deno GREEN; full `deno test functions/` still GREEN (003 suites unchanged)

**Checkpoint**: Arabic errors live on all endpoints.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T018 Run ALL quickstart.md gates 1–6 (SQL suite, deno suite, curl message_ar sweep, backlog pagination probe, regression incl. `node supabase/e2e/book_pay_flow.mjs`, hygiene scans). Paste actual outputs
- [X] T019 Hygiene assertions: `grep -c caption supabase/migrations/0049_accessibility_foundations.sql` = 0; `git diff main -- supabase/migrations/` touches only 0049; no secrets; no CONCURRENTLY
- [X] T020 [P] Owner review of the 6 seeded Arabic error sentences (wording, one short sentence each) — data-level edits welcome, no code change

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 → Phase 2**: setup before schema
- **Phase 2 BLOCKS all stories** (tables/catalog are shared substrate)
- **US1 / US2 / US3 independent of each other** — parallelizable after Phase 2. Within stories: tests before implementation (TDD); US2's T011/T013 are independent of US1 entirely

### User Story Dependencies

- US1: T005–T007 (parallel tests) → T008 → T009
- US2: T010, T011 (parallel) → T012 → T013
- US3: T014, T015 (parallel) → T016 → T017

### Parallel Opportunities

```
After Phase 2:  T005 ∥ T006 ∥ T007 ∥ T010 ∥ T011 ∥ T014 ∥ T015   (all test-writing, different sections/files)
Story lanes:    US1 lane ∥ US2 lane ∥ US3 lane
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1 + Phase 2 → 2. US1 (T005–T009) → 3. STOP, validate gates 1+4 → demo: publish refusal + backlog screen data.
4. Then US2 (delivery automation) → demo: WhatsApp outbox event.
5. Then US3 (Arabic errors) → demo: curl sweep shows `message_ar`.

### Notes

- Every implementation task = one commit (`feat(scope):` / `test(scope):`), test-first per repo protocol
- Migration stays ONE file (0049) across all stories — append sections, never edit applied files
- No caption/transcript metadata anywhere (owner decision — quickstart gate asserts 0 occurrences)
- Review loop (fast model implements, reviewer verifies) same as 003
