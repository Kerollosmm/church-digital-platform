# Research: Payment Simplification & System Design Review

**Spec**: 011 — Manual Payment Verification (replaces the Paymob online-checkout leg)
**Date**: 2026-08-22
**Question**: Is the current booking workflow + Paymob payment integration the right design for a church event-booking platform of this size, or should payment collection move to manual wallet-transfer proof (screenshot + reference number) verified by an admin? Which other subsystems are over-built for actual usage?

---

## 1. Verdict up front

Replace the Paymob leg with admin-verified manual payments. The integration was built for a merchant account that **does not exist** (owner-confirmed, never onboarded), it cannot process a real pound today, and the platform's operating model is *already* human-in-the-loop per booking. Mainstream church software treats manual/offline payment as a first-class workflow, not a compromise. Removal deletes ~1,500 lines of code, 6 environment secrets, one cron job, and an entire failure class (webhooks, HMAC, idempotency, reconciliation), while keeping every guarantee that matters (seat locks, expiry, waiting-list promotion, money-boundary seam).

---

## 2. Current-state inventory: what the Paymob leg costs

All paths verified against source on branch `010-fix-review-findings` @ working tree.

### 2.1 Edge functions and shared code (~1,000 lines Deno)

| File | Lines | Role |
|---|---|---|
| `supabase/functions/_shared/paymob.ts` | 451 | Adapter: token-session cache (`paymob.ts:197-247`), order registration (`:249-357`), refund (`:359-401`), order status (`:403-442`), 20-field HMAC serialization (`:79-135`) |
| `supabase/functions/paymob-checkout/index.ts` | 216 | Creates checkout session → iframe URL for the app |
| `supabase/functions/paymob-webhook/index.ts` | 129 | Receives async payment callbacks; HMAC validation |
| `supabase/functions/reconcile-payments/index.ts` | 126 | Nightly sweep of stuck/unknown payment states |
| `supabase/functions/_shared/payments-gateway.ts` | 74 | The sanctioned write seam — **keep**, reused by new RPCs |

### 2.2 Database surface

- `payment_status` enum with six values incl. gateway-specific ones (`CREATED`,`PAID`,`FAILED`,`REFUNDED`,`REFUND_PENDING`,`PENDING`) — `migrations/0001_init_schema.sql:8`
- Payment RPCs added forward-only: `0063_service_role_grants_and_payment_rpc.sql`, `0064_transition_owner_guard.sql`, `0065_webhook_payment_rpc.sql` (webhook idempotency RPC)
- Refund plumbing spreads wider than payments: `apply_payment` enqueues a `PAYMOB_REFUND` outbox row on late-webhook refunds (`0012_apply_payment.sql:24-31`), repeated in `0028_fix_paid_amount_snapshot.sql:97-99`, seeded by emergency override (`0017_emergency_override.sql:44-47`)
- Cron jobs: `reconcile-payments` daily 03:30 (`0013_reconcile_cron.sql:4-10`); event-dispatcher drains outbox every minute (`0016_whatsapp_sender_cron.sql:4-10`)
- Dead residue already present: video-payment webhook landing in `0019_videos.sql:84` refers to a feature that was cancelled (video pivot memory)

### 2.3 Secrets and configuration

Six Paymob env vars are read across functions: `PAYMOB_API_KEY`, `PAYMOB_INTEGRATION_ID`, `PAYMOB_CARD_INTEGRATION_ID`, `PAYMOB_IFRAME_ID`, `PAYMOB_HMAC_KEY`, `PAYMOB_HMAC_SECRET`. Notably these live as **plain edge-function env vars** — they are absent from the vault preflight checklist (`0055_vault_preflight.sql`, which requires only `COMPLAINTS_KEY`, `SUPABASE_URL`, `SERVICE_ROLE_KEY`). Function entries in `supabase/config.toml:407-411`.

### 2.4 Client surface

Mobile: checkout session model + redirect/iframe screen with retry logic spans 9 files (`models/booking_checkout_session.dart`, `features/booking/payment_redirect_screen.dart:12-80`, `controllers/booking_flow_controller.dart`, `repositories/{booking_repository,supabase_booking_repository}.dart`, router/routes strings). Admin: `payments_admin_screen.dart` is a read-only list today (`payments_admin_screen.dart:16-42`).

### 2.5 Test surface that would be deleted with it

Deno: `_tests/paymob_test.ts`, `_tests/payments_gateway_test.ts` (partially rewritten), `paymob-{checkout,webhook}/index_test.ts`, `reconcile-payments/index_test.ts`; SQL suites `tests/0063_service_role_grants_test.sql`, `0064_transition_owner_guard_test.sql`, `0065_webhook_payment_rpc_test.sql`. Runner: `scripts/test-sql.js` executes each `supabase/tests/*.sql` via psql TAP.

### 2.6 What removal does NOT touch (safety preserved)

- Seat-lock expiry: `expire_stale_bookings()` runs **every minute**, cancels stale `PENDING_PAYMENT` bookings, promotes waiting list (`0010_lock_expiry_cron.sql`, hardened `0053_backend_security_and_correctness_fixes.sql:226-252`). This is payment-method-agnostic — the manual flow inherits seat-release safety unchanged.
- Booking state machine and transitions (`AWAITING_CALL` → admin phone confirm → `CONFIRMED`): untouched.
- Money boundary: all writes stay inside SECURITY DEFINER RPCs behind `payments-gateway.ts` (spec 010's core achievement).

---

## 3. External practice benchmark: how comparable products handle this

Method note: session search infrastructure (WebSearch/WebFetch summarizer) was down; research done via direct fetches through a reader proxy against official vendor documentation. Fraud-statistics sources could not be retrieved this session — flagged in §7 follow-ups.

### 3.1 Breeze ChMS (small-church management, closest size analog)

Source: [Accepting Payments on Forms — Breeze support](https://support.breezechms.com/hc/en-us/articles/360001326413-Accepting-Payments-on-Forms) (fetched 2026-08-22)

- Forms explicitly support a **"Pay Later" registration path**: setting the payment amount to zero "completely bypass[es] the payment section… helpful if you are including multiple payment options on the form and one of them is 'Pay Later'". Register-now, settle-manually is a shipped pattern.
- Online processors are **region-gated**: USA/Canada = cards only ("Forms cannot accept ACH"), EU = PayPal, elsewhere = Stripe/PayPal. An Egyptian deployment lands in "Stripe/PayPal" territory — i.e., mainstream small-church tooling does not serve Egyptian wallets natively at any price point.
- Card fees 2.9% + $0.30/transaction; guidance is to bake fees into ticket price.

### 3.2 Planning Center Registrations (US market leader, larger but instructive)

Sources: [Payments overview](https://help.planningcenter.com/en/139318-payments.html), [Cash and check](https://help.planningcenter.com/en/138396-cash-and-check.html) (both fetched 2026-08-22)

- Even at scale, Planning Center ships **manual entry of cash/check donations via batches** as first-class Giving workflows, with operational guidance (split cash vs checks into separate batches, envelope batch numbers, anonymous-gift handling).
- Interpretation: human review/recording of non-card money is institutionalized practice in church software, not a hack for poor markets.

### 3.3 Egyptian rails

- InstaPay is Egypt's CBE-operated instant payment system, launched March 2022 ([Wikipedia: Central Bank of Egypt / InstaPay](https://en.wikipedia.org/wiki/InstaPay)); transfers settle wallet-to-wallet/bank-to-bank with sender-side confirmation receipts.
- Vodafone Cash remains the dominant mobile wallet; P2P transfers produce an SMS confirmation with transaction reference on the sender's phone. (Official page is JS-rendered; mechanics stated here from general knowledge — verify wording during spec review.)
- **Design principle that needs no external citation**: in any manual-proof flow, the member-submitted screenshot is supporting evidence only; the source of truth is the **church's own** wallet/statement log matched by reference number + amount + time. This single rule neutralizes the classic fake-screenshot fraud class regardless of statistics.

### 3.4 Benchmark synthesis for our context

1. Comparable products treat "register now / pay manually / human confirms" as legitimate, sometimes preferred, especially outside US card rails.
2. No mainstream ChMS serves Egyptian wallets — so "just use a gateway" was always going to mean Paymob-specific onboarding work (KYC, commercial registration — historically hard for churches) plus the integration we already carry.
3. Our platform *already* phones every booker before confirming (`AWAITING_CALL` lifecycle, `memory-bank/activeContext.md:40-46`). Verification labor is not new; the Paymob leg automates the one step that was never actually running.

---

## 4. Full-system simplification audit

Verdicts with caller evidence (greps over apps/, test-apps/, migrations/, config.toml):

| Subsystem | Evidence | Verdict |
|---|---|---|
| paymob trio + adapter + webhook RPC + reconcile cron | §2; zero real transactions possible (no account) | **Delete** (git history preserves reversibility) |
| `offline-sync` function (78 ln) | **Zero callers** anywhere in apps, test-apps, migrations | **Delete** (confirm no roadmap intent first) |
| `diagnostic-engine` (161 ln) | Called only by test-apps superadmin harness; referenced by `0054_admin_security_alert_template.sql` | Keep as dev tooling; do not extend |
| `analytics-export` (132 ln) | Real consumer: `apps/admin/lib/features/analytics/export_report_button.dart` | **Keep** |
| `event-dispatcher` (409 ln) | Live cron consumer; sends WhatsApp templates (`booking_payment_received` `0012_apply_payment.sql:45-46`, `booking_apology` `0017_emergency_override.sql:33-34`) and FCM push; also handles `PAYMOB_REFUND` rows | **Keep core** (notifications); delete `PAYMOB_REFUND` handler with Paymob. Flag: requires `WHATSAPP_TOKEN`/`FCM_*` env vars — same "built ahead of provider" risk class as Paymob if unprovisioned |
| PGCrypto complaints encryption | Key managed in vault (`0055_vault_preflight.sql` requires `COMPLAINTS_KEY`); complaints are sensitive pastoral content | **Keep** — privacy value justifies modest complexity |
| Admin analytics screens | Stakeholder-facing, read-only, no money-path coupling | Keep |
| Bookings state machine + expiry cron + waiting list | Working, tested, method-agnostic | **Untouched** |
| `payments-gateway.ts` seam shape | Spec 010 deliverable; correct pattern | Keep; new proof RPCs go through it |

Not audited this pass (out of scope): OTP/SMS auth flow (auth-critical, recently hardened).

---

## 5. Trade-off analysis: Paymob checkout vs manual proof verification

| Axis | Paymob checkout (current) | Manual proof verification (proposed) |
|---|---|---|
| Can it work today? | No — no merchant account, KYC/commercial docs needed | Yes — wallets/church bank account already exist |
| Code carried | ~1,500 ln + 3 crons' worth of machinery | Proof table + 3 RPCs + queue UI + upload screen |
| Failure classes | Webhook loss, HMAC mismatch, stuck sessions, reconcile drift, late-refund races | Human error reviewing; mitigated by own-statement matching |
| Fraud exposure | Chargebacks/fraud handled upstream by gateway | Fake screenshots — neutralized by verifying reference+amount against church's own log, not the image |
| Ops load per booking | Near-zero when healthy; high when broken (stuck payments) | One approve/reject tap; folds naturally into the existing `AWAITING_CALL` phone call — admin can confirm the transfer during the call they already make |
| Fees | ~2.9% + fixed per transaction (Breeze-documented typical rates §3.1) | None |
| Refunds | Automated API refund path (never exercised) | Fully manual cash/wallet return — acceptable at parish volumes |
| Auditability | Gateway dashboard + DB rows | DB rows + screenshots + church statement = sufficient at this scale |
| Reversibility | Deleting now loses nothing; re-adding later means re-onboarding anyway | Seam kept: a gateway can be reintroduced behind the same RPC boundary if the church ever onboards |

## 6. Recommendation

Proceed with Spec 011 as drafted: manual proof submission (Vodafone Cash / InstaPay / cash-in-person), admin verification queue, cash direct-marking, deletion of the entire Paymob stack, notifications re-pointed to proof approval. Land **before** feature 008 builds its money paths on top.

## 7. Follow-ups / open items

- Verify exact Vodafone Cash SMS confirmation wording and InstaPay receipt fields during implementation testing (official pages JS-rendered this session).
- Fraud-pattern literature (fake-screenshot generators prevalence) unretrieved due to search outage — the mitigation design does not depend on it.
- Confirm nobody holds roadmap intent for `offline-sync` before deletion.
- Confirm whether WhatsApp Cloud API credentials exist; if not, event-dispatcher joins the "built ahead of provider" list and notification delivery should be marked best-effort.

---

## 8. Phase 0 Technical Decisions (speckit-plan)

Format: Decision / Rationale / Alternatives considered. All resolved — the spec carried zero NEEDS CLARIFICATION markers.

### D1 — Proof image storage: private Supabase Storage bucket `payment-proofs`

- **Decision**: New private bucket, object path `{tenant_id}/{booking_id}/{proof_id}.<ext>`; RLS: member INSERT/SELECT only under own prefix (`auth.uid()` ownership via booking join policy), admin tiers SELECT all; no anon access; bucket policies follow AGENTS.md Storage RLS & Grants guard (explicit `ENABLE ROW LEVEL SECURITY` on `storage.objects`, granular DML, `TO authenticated`).
- **Rationale**: Platform-native, zero new infrastructure; path scheme makes policy predicates simple and auditable; private-by-default matches screenshot sensitivity.
- **Alternatives**: base64 column in Postgres (rejected: row bloat, no streaming/thumbnailing); external object storage (rejected: new secret surface for zero gain at parish scale).

### D2 — Three new SECURITY DEFINER RPCs inside the existing seam

- **Decision**: `submit_payment_proof`, `approve_payment_proof`, `reject_payment_proof` — registered in `_shared/payments-gateway.ts` as thin wrappers, implemented as plpgsql with fixed `search_path`, REVOKE-then-grant (`authenticated` for submit; `ADMIN|SUPER_ADMIN` gate inside approve/reject), audit trigger coverage inherited.
- **Rationale**: Constitution II + conventions "money lives in SQL"; keeps exactly one sanctioned write doorway (spec 010's core win); apps never learn table shapes.
- **Alternatives**: generic proof-transition RPC (rejected: loses per-action guards and idempotency clarity); client-side table writes under RLS only (rejected: violates money-boundary locked decision).

### D3 — Payment row lifecycle reuses existing statuses and procedures verbatim

- **Decision**: Submission snapshots a `CREATED` payment via the existing `create_pending_payment`; approval executes the untouched `apply_payment` (which already encodes stale/cancelled → `REFUND_PENDING` semantics from migration 0012); rejection mutates nothing financial.
- **Rationale**: Zero drift between online-era guarantees and manual era — the race tests written against Paymob webhooks remain valid for approvals.
- **Alternatives**: new enum values like `PROOF_PENDING` on payments (rejected: additive-only territory churned for nothing; proofs are their own entity).

### D4 — Payout details as first-class config table `payout_channels`

- **Decision**: Seeded rows (channel, display_name_ar, account_number, holder_name); super-admin writable via guarded update path; readable by authenticated members.
- **Rationale**: Number changes become data edits, not releases (spec US4); typed columns beat free-form KV.
- **Alternatives**: hardcode numbers in app strings (rejected: requires release to change); generic `app_settings` key-value (rejected: weaker validation, wider write blast radius).

### D5 — Gateway deletion ships as forward migrations + code removal in one logical commit

- **Decision**: Migration drops/revokes webhook-path DB objects and unschedules the reconcile cron; repository deletion removes functions dirs + tests + `_shared/paymob.ts` + `PAYMOB_*` env reads (including the dispatcher's `PAYMOB_REFUND` branch) + `config.toml` blocks + mobile checkout-session flow; verification greps assert zero live references.
- **Rationale**: FR-012 single commit keeps the tree bisectable; forward-only rules honored for DB side; git history preserves reversibility.
- **Alternatives**: feature-flag keep-alive (rejected: repo rule deletes unused code outright); gradual deprecation (meaningless pre-launch).

### D6 — Expiry interplay needs no engine change

- **Decision**: `expire_stale_bookings` untouched; a pending proof is just a `PENDING_PAYMENT` booking to it. Registered test proves cancel+promotion still fire with a proof attached; orphaned-proof approval fails closed via existing status guards.
- **Rationale**: Payment-method-agnostic safety was verified during research (migrations 0010/0053); duplicating its logic for proofs would be a defect.
- **Alternatives**: pause expiry while proof pending (rejected: unbounded seat hoarding by resubmission).
