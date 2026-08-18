# Quickstart: Validate 004-accessibility-foundations

**Prereqs**: 003 merged (main ≥ 003 tip); local stack up (`npx supabase start`); migration 0049 applied via reset.

## 1. SQL suite (gates, delivery, catalog, backlog, negative auth)

```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/run_all.sql
```

Expected: new `0049_accessibility_test.sql` passes — publish refusal with missing alt (SC-002), decorative allowed, Arabic preserved verbatim (FR-003), `deliver_personal_video`: success path (video UNLISTED + access granted + one `video_ready` event with buyer phone), `UNKNOWN_PHONE` refusal sends nothing, `PAYMENT_INVALID` refusal, idempotent retry (same video_id, no second event), catalog seeded with 6 Arabic rows, backlog returns image offenders matching fixture snapshot + keyset pages without skip/duplicate (SC-004), anon/authenticated execution of all 4 RPCs denied.

## 2. Deno suite (messages cache + respond extension + dispatcher template)

```bash
cd supabase && deno test --allow-env --allow-net functions/
```

Expected: `_tests/messages_test.ts` — cache hit within TTL, reload after TTL (fake clock), lookup failure ⇒ FALLBACK Arabic; `http_test.ts` extended — 4xx/5xx body contains non-empty `message_ar`; `event-dispatcher` suite — `video_ready` template sends WhatsApp and stamps `link_sent_at` (fake client).

## 3. Error message sweep (SC-003)

```bash
for ep in paymob-checkout offline-sync analytics-export otp-sms; do
  curl -s "$FUNC_URL/$ep" -H "Authorization: Bearer garbage" | grep -o '"message_ar":"[^"]*"'
done
# expect: non-empty Arabic per endpoint; unknown-code probe returns FALLBACK sentence
```

## 4. Backlog pagination probe (SC-004)

Seed ≥ 25 undescribed images; call `get_backlog(NULL, NULL, 10)` three times passing cursors; assert union = full fixture set, no duplicates; delete 5 rows mid-walk, continue paging — remaining rows unchanged (keyset stability).

## 5. Regression (SC-005 / FR-010)

- `run_all.sql` full pass (all pre-0049 suites unchanged).
- `deno test functions/` full pass (003 suites unchanged).
- Booking/payment/e2e flow unchanged: `node supabase/e2e/book_pay_flow.mjs`.
- Global video purchase flow unchanged: existing `purchase_video` tests still green (no `videos` schema change).

## 6. Hygiene scans

```bash
grep -rn "supabase.co\"\|eyJhbGciOi" supabase/functions/ supabase/migrations/ | grep -v _test   # 0
grep -c "CREATE INDEX CONCURRENTLY" supabase/migrations/0049_accessibility_foundations.sql  # 0
grep -c "caption" supabase/migrations/0049_accessibility_foundations.sql                   # 0 (no caption metadata)

# Assert changed migration files match exact set: 0044 (hardened in-place, covered by 0051 forward migration), 0049, 0050, 0051
git diff main --name-only -- supabase/migrations/ | sort
# expect exactly:
# supabase/migrations/0044_storage_buckets.sql
# supabase/migrations/0049_accessibility_foundations.sql
# supabase/migrations/0050_explicit_read_grants.sql
# supabase/migrations/0051_storage_objects_rls_guard.sql

# Assert get_backlog is executable by service_role only (revoked from anon and authenticated)
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "
  SELECT grantee, privilege_type 
  FROM information_schema.routine_privileges 
  WHERE routine_schema = 'public' AND routine_name = 'get_backlog';
"
# expect: grantee is service_role (and postgres/admin superuser) only; neither anon nor authenticated.
```
