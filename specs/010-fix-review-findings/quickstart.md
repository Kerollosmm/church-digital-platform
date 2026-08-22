# Quickstart: Review Findings Remediation Validation

**Feature**: 010-fix-review-findings

Prerequisites: local stack up (`npx supabase start`, then `npx supabase db reset`), Deno available, Flutter available.

## 1. Backend gates (must all be green)

```powershell
# Full SQL suite — parse TAP output, never trust exit code
node scripts/test-sql.js          # expect: 55/55 suites PASS (54 existing + 0064)

# Edge function unit tests
deno test --allow-env --allow-net supabase/functions/   # expect: all PASS, incl. new leak + gateway assertions
```

Proof points to eyeball in output:
- `0064_transition_owner_guard_test.sql` — non-owner `apply_payment` denied (0 rows), owner path succeeds, service_role succeeds
- Webhook/checkout/reconcile tests assert payment changes go through RPC-mocking seam, not table client
- Failure-path tests assert bodies contain code + Arabic sentence and NO library/upstream substrings

## 2. Credential scan (FR-006 / SC-004)

```powershell
Select-String -Path test-apps\* -Pattern "SERVICE_ROLE|password123" -Recurse   # expect: no matches in committed files
```

Then run the harness (`test-apps/run.ps1`): superadmin flows sign in as seeded SUPER_ADMIN over anon client; setup-generated passwords land in an untracked local file.

## 3. Admin app gates (US4 + US6)

```powershell
flutter analyze; flutter test   # workdir apps/admin — expect: clean, all tests pass
```

Manual check: sign in as admin → exactly one identity round-trip (network tab / logs show role lookup only, no call to removed priest-era function). Sign in as USER-role member → access-denied with same Arabic message as before.

Grep proof:

```powershell
Select-String -Path apps\admin\lib\features\*\*_screen.dart -Pattern "\.from\('|\.rpc\(|Supabase\.instance"   # expect: no matches
```

## 4. Mobile regression gate (untouched but must stay green)

```powershell
flutter analyze; flutter test   # workdir apps/mobile — expect: clean
```

## 5. Docs diff (SC-006)

Compare conventions.md §Enums against live types:

```sql
select t.typname, array_agg(e.enumlabel order by e.enumsortorder)
from pg_type t join pg_enum e on e.enumtypid = t.oid
group by t.typname order by t.typname;
```

Expect documented lists == query output (slot_status OPEN/CLOSED, waitlist WAITING/OFFERED, roles USER/ADMIN/SUPER_ADMIN).

## 6. Harness count (SC-008)

```powershell
Test-Path test_portal    # expect: False
Test-Path test-apps      # expect: True
```

Full pass = SC-001…SC-010 demonstrable; proceed to commit per remediation area (`fix(scope):` one logical change each).
