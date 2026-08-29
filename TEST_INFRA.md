# E2E Test Infra: Church Platform Extensions

## Test Philosophy
- Opaque-box, requirement-driven. No dependency on implementation internals.
- Verification across 4 tiers (Feature Coverage, Boundary/Corner, Cross-Feature Combinations, Real-World Workload Scenarios).
- Multi-tier target coverage: SQL pgTAP test suites, Deno test suites, Flutter unit & widget tests.

## Feature Inventory & Test Mapping
| # | Feature | Requirement Source | Tier 1 | Tier 2 | Tier 3 | Tier 4 |
|---|---------|-------------------|:------:|:------:|:------:|:------:|
| 1 | Priest Schedule Exclusion Constraints | Spec 009 (R1) | 5 | 5 | ✓ | ✓ |
| 2 | Priest & Venue Allocation RPC | Spec 009 (R1) | 5 | 5 | ✓ | ✓ |
| 3 | Priest Availability Query | Spec 009 (R1) | 5 | 5 | ✓ | ✓ |
| 4 | Sacramental Records & Token Generation | Spec 010 (R2) | 5 | 5 | ✓ | ✓ |
| 5 | Public QR Privacy Verification | Spec 010 (R2) | 5 | 5 | ✓ | ✓ |
| 6 | Storage Private Bucket & RLS | Spec 010 (R2) | 5 | 5 | ✓ | ✓ |
| 7 | Sunday School Classes & Servant Gate | Spec 011 (R3) | 5 | 5 | ✓ | ✓ |
| 8 | Bulk Attendance & Uniqueness Invariant | Spec 011 (R3) | 5 | 5 | ✓ | ✓ |
| 9 | Mobile Offline Sync Dispatch | Spec 011 (R3) | 5 | 5 | ✓ | ✓ |
| 10 | Admin Allocation & Analytics UI | Specs 009-011 | 5 | 5 | ✓ | ✓ |

## Test Architecture
- **SQL Runner**: `node scripts/test-sql.js` executing `supabase/tests/run_all.sql` with isolated transactions.
- **Edge Runner**: `deno test` across `supabase/functions/`.
- **Flutter Runner**: `flutter test` across `apps/mobile/` and `apps/admin/`.

## Real-World Application Scenarios (Tier 4)
| # | Scenario | Features Exercised | Complexity |
|---|----------|--------------------|------------|
| 1 | End-to-end Event Booking to Priest/Hall Allocation with WhatsApp dispatch | F1, F2, F3, F10 | High |
| 2 | Sacramental Certificate Issuance, PDF private storage, and Public Anonymous QR Verification | F4, F5, F6, F10 | High |
| 3 | Sunday School Servant assignment, classroom roster bulk attendance submission and unique conflict check | F7, F8, F9, F10 | High |
| 4 | Concurrent double-booking rejection on priest commitments and hall availability | F1, F2, F3 | High |
