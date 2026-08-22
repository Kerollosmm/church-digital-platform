# Feature Specification: Manual Payment Verification

**Feature Branch**: `011-manual-payment-verification`

**Created**: 2026-08-22

**Status**: Draft

**Input**: User description: "Feature 011: Manual Payment Verification — replace the Paymob online-checkout leg (never onboarded, zero real transactions) with admin-verified manual payments: member pays via Vodafone Cash / InstaPay / cash in person and submits transfer reference + screenshot proof; admin verifies against church's own wallet statement via a review queue; existing apply_payment → AWAITING_CALL flow unchanged; full deletion of the Paymob stack."

## Context

The electronic payment gateway was built for a merchant account that does not exist (owner-confirmed 2026-08-22): the integration cannot process a real transaction today. Meanwhile every booking already requires a mandatory human step — an administrator phone-confirms each booking before it is confirmed. ADR 0003 (2026-08-22) records the owner decision to retire the gateway rail and make admin-verified manual payment the only payment rail. Research (`research.md`) shows this matches both the platform's operating model and mainstream church-software practice. This feature delivers that replacement end to end while preserving every financial guarantee already in place: the seat-lock expiry engine, the booking state machine, and the single sanctioned write path for money.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Member pays by wallet and submits proof (Priority: P1)

A member books a slot and reaches the payment step, where the church's current wallet numbers are displayed for copying. They transfer the amount from their own wallet (Vodafone Cash or InstaPay), then submit a payment proof through the app: which channel they used, the phone number the transfer came from, the transfer's reference number, the amount, and a screenshot of the transfer confirmation. The submission is acknowledged immediately; the seat stays locked under the existing pending-payment timer until a human reviews the proof.

**Why this priority**: Without proof submission there is nothing to verify — this is the entry point of the entire replacement flow and delivers standalone value (a member can complete their part without any gateway).

**Independent Test**: A member with a pending-payment booking can submit a complete proof in under two minutes and sees confirmation that it awaits review; another member cannot submit a proof for someone else's booking.

**Acceptance Scenarios**:

1. **Given** a member with a pending-payment booking, **When** they submit a wallet proof with channel, sender number, reference, amount, and image, **Then** the proof is recorded as awaiting review, linked only to their booking, and the booking remains pending payment.
2. **Given** a wallet-channel proof submitted without an image, **When** the member tries to send it, **Then** submission fails with the standard Arabic error sentence and nothing is recorded.
3. **Given** member B attempting to attach a proof to member A's booking, **When** the attempt executes, **Then** it is denied with zero changes.

---

### User Story 2 - Admin verifies or rejects proofs from one queue (Priority: P1)

An administrator opens a review queue listing every proof awaiting decision: booking, member, claimed channel, sender number, reference number, amount, and the screenshot. The administrator checks the church's own wallet/statement records for that reference, amount, and time. Approving advances the booking exactly as a successful online payment would have — into the awaiting-call state that precedes the mandatory confirmation phone call. Rejecting records one of the standard Arabic reasons, shows it to the member, and leaves the booking pending so the member can correct details and resubmit before the seat lock expires. Approving the same proof twice changes nothing the second time.

**Why this priority**: This is the money decision; its guards (who may decide, idempotency, non-owner denial) are where financial correctness lives.

**Independent Test**: A staff account can move a pending proof to approved (booking advances) or rejected (member sees reason, resubmission works); a non-staff account can do neither; double approval has no second effect.

**Acceptance Scenarios**:

1. **Given** a pending proof whose details match the church statement, **When** an admin approves it, **Then** the linked payment is marked paid through the sanctioned path and the booking reaches the awaiting-call state.
2. **Given** the same proof approved twice, including by two admins at once, **When** the second approval lands, **Then** it is denied idempotently with no duplicate transition.
3. **Given** a rejected proof, **When** the member submits corrected details before lock expiry, **Then** the new attempt appears in the queue and the rejected one remains as visible history.
4. **Given** a non-admin caller invoking approve or reject, **When** either executes, **Then** denial occurs with zero rows changed.
5. **Given** an amount that does not match the church statement, **When** the reviewer rejects it, **Then** the rejection reason shown to the member is the mismatch sentence from the frozen catalog.

---

### User Story 3 - Cash taken in person is marked directly (Priority: P2)

When a member pays cash at the church office to a servant or treasurer, no transfer proof exists. An authorized staff member marks the booking paid directly through the same approval surface, choosing the cash channel with no image requirement and optionally noting who collected the money.

**Why this priority**: Same financial decision as Story 2 with a simpler input shape; it reuses the same guards and cannot be exploited differently.

**Independent Test**: Staff can mark cash received on a pending-payment booking with no image attached and the booking advances identically to a wallet approval.

**Acceptance Scenarios**:

1. **Given** a pending-payment booking, **When** staff mark cash received with a collector note, **Then** the booking reaches awaiting-call and the payment record shows the cash channel and note.

---

### User Story 4 - Super-admin maintains the church payout details (Priority: P2)

The wallet numbers and account names members must transfer to are data, not code: a super-admin can update them from the admin app, and the member payment step always shows the current values. Regular admins cannot change them.

**Why this priority**: Operationally necessary for the flow (numbers change), but low-frequency and low-risk.

**Independent Test**: Changing a payout number as super-admin is reflected on the member payment step; the same change attempted by a regular admin is denied.

**Acceptance Scenarios**:

1. **Given** configured payout channels, **When** a member opens the payment step, **Then** the current numbers and holder names are shown with copyable values.
2. **Given** a regular admin editing payout configuration, **When** submitted, **Then** the change is denied.

---

### User Story 5 - The gateway stack is deleted outright (Priority: P2)

Everything that existed only to serve the electronic gateway goes away: its checkout, webhook, and reconciliation functions with all their tests, the shared adapter, the webhook-specific database procedure path, its scheduled jobs, its environment secrets, its configuration entries, and the mobile checkout/redirect screens replaced by the proof flow. Nothing is kept "just in case" — history preserves reversibility.

**Why this priority**: Dead weight misleads every future change; deletion is the point of the feature, but it lands only after Stories 1–3 work.

**Independent Test**: A repository-wide scan finds zero live references to the retired gateway outside historical migrations, and every remaining automated suite passes.

**Acceptance Scenarios**:

1. **Given** the landed feature, **When** the repository is scanned for the gateway's names, variables, and config entries, **Then** zero live references remain (applied historical migrations excepted).
2. **Given** the full backend and both app test suites, **When** they run after removal, **Then** all pass with the deleted suites excluded.

---

### User Story 6 - Notifications fire on verification, not on gateway callback (Priority: P3)

The notification previously sent when an online payment succeeded is now sent when a proof is approved, with the same template and content. If the notification provider is not configured, the message is still recorded and delivery remains best-effort exactly as today — never blocking the money path.

**Why this priority**: Timing-only change on an optional subsystem.

**Independent Test**: Approving a proof enqueues the same payment-received notification previously triggered by gateway success; rejecting enqueues nothing.

**Acceptance Scenarios**:

1. **Given** proof approval, **When** the transaction completes, **Then** the payment-received notification is queued exactly as before.

### Edge Cases

- What happens when the seat lock expires while a proof still awaits review? The expiry engine cancels the booking and frees/promotes the seat exactly as it does today. A later approval attempt on the orphaned proof fails cleanly with a catalog sentence; if money was already transferred, refund is a documented manual step (cash/wallet return).
- How does the system handle a claimed amount that differs from the church statement? The reviewer rejects with the mismatch reason; v1 performs no automatic matching.
- What about the same reference number submitted twice for different bookings? Not technically blocked; reviewers matching amount + time + sender against the statement surface duplicates naturally.
- What if the screenshot upload fails mid-submission? Wallet submissions fail atomically — no proof exists without its required image. Cash needs none.
- What if approval races the expiry sweep? One outcome wins deterministically inside the same transactional guarantee class the transition engine already provides; seat accounting is never lost.
- Can a member spam resubmissions? Yes, within their lock window; every attempt is visible history for the reviewer, and expiry ends the cycle.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Proof submission MUST be owner-only: a member can create proofs exclusively for their own pending-payment booking; any other caller is denied with zero changes.
- **FR-002**: Approval and rejection MUST be restricted to administrative tiers; approval MUST drive the exact same paid-transition used by successful payments so advancement guarantees are unchanged.
- **FR-003**: Double approval MUST be idempotent-denied within one transaction; concurrent approve-vs-expiry MUST resolve deterministically with no lost seat accounting.
- **FR-004**: Wallet channels (Vodafone Cash, InstaPay) MUST require a screenshot at submission; the CASH channel MUST NOT allow or require one.
- **FR-005**: Screenshots MUST be stored privately: a member can read/write only their own uploads; administrative tiers can read all; anonymous access MUST be impossible.
- **FR-006**: Payout channel details MUST come from editable configuration writable only by super-admin and readable by authenticated users.
- **FR-007**: Rejection reasons MUST be chosen from the frozen Arabic error-catalog sentences (no new codes); the member MUST see the reason on their booking screen and may resubmit until lock expiry.
- **FR-008**: All money-state changes introduced by this feature MUST execute inside the sanctioned SECURITY DEFINER seam with REVOKE-then-grant privileges; no new direct table writes anywhere.
- **FR-009**: Every schema change ships forward-only as a new numbered migration paired with a registered transactional test suite proving: owner-submit allowed / non-owner denied, staff-only decisions, idempotent double-approval, reject→resubmit→approve lifecycle, and unchanged expiry behavior with a proof pending. Suite results are judged by parsed output, never exit codes alone.
- **FR-010**: The member app replaces checkout/redirect screens with the proof flow: channel picker, sender number, reference, amount, image attach, and display of current payout details; all network access goes through repository interfaces; Arabic strings route through the shared string catalog.
- **FR-011**: The admin app gains a pending-proofs queue (thumbnail, claimed fields, approve/reject-with-reason in one screen) built on the established typed-repository pattern; tests exercise repositories, not private widget internals.
- **FR-012**: Deletion scope ships as one logical commit: gateway functions + tests, shared adapter, webhook procedure call path, scheduled reconcile job, gateway env vars, config entries, `PAYMOB_REFUND` handler branch, and mobile checkout-session/redirect modules.
- **FR-013**: The expiry engine, transition engine, waiting-list promotion, and slot logic MUST remain untouched; regression coverage proves a booking with a pending proof still expires and promotes normally.
- **FR-014**: The payment-received notification trigger moves from gateway success to proof approval with template name and payload unchanged; missing provider credentials degrade to recorded-but-undelivered as today.
- **FR-015**: Each area (schema+RPCs, member app, admin app, deletion, notifications) MUST land as an independently committable change keeping the tree green.

### Key Entities *(include if data involved)*

- **PaymentProof**: the member's claim that money moved — channel (Vodafone Cash / InstaPay / CASH), sender phone, reference number, claimed amount, optional screenshot, status (awaiting / approved / rejected), rejection reason, reviewer and review time, collector note (cash only), submission time. Many proofs may exist per booking; the newest drives review.
- **PayoutChannel**: what the church publishes for members to pay into — channel, Arabic display name, account number, holder name. Super-admin editable data.
- **Payments**: existing statuses reused verbatim; submission snapshots a created row, approval drives the existing paid-transition, rejection leaves the snapshot linked for resubmission. No new statuses.
- **Error catalog**: frozen five codes reused verbatim; humans always see the Arabic sentence, never raw errors.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A first-time member completes proof submission in under 2 minutes from the payment step, measured in a moderated walkthrough.
- **SC-002**: An administrator decides a proof in under 30 seconds using only the queue screen (open + one decision action).
- **SC-003**: Repository scan reports zero live references to the retired gateway across code, tests, and configuration after landing.
- **SC-004**: 100% of non-owner submission attempts and non-staff decision attempts are denied with zero changes, proven by registered tests.
- **SC-005**: A booking with a pending proof still releases its seat within the standard expiry window in 100% of test runs, with waiting-list promotion intact.
- **SC-006**: A member who submitted mismatched details successfully resubmits corrected details before lock expiry in the guided walkthrough.
- **SC-007**: All automated suites pass after landing: transactional SQL suites (parsed output), backend function suites, and both apps' analysis-and-test gates.

## Assumptions

- The church operates at least one working Vodafone Cash number and/or InstaPay alias and staff can consult its statement during review (owner-selected channels, 2026-08-22).
- Parish booking volumes keep human review tractable; if volumes ever outgrow it, an electronic gateway could be reintroduced behind the unchanged seam — requiring merchant onboarding, not redesign.
- Notification provider credentials may not be provisioned; delivery is best-effort and never blocks money movement.
- Proof retention follows booking lifetime for v1; a cleanup policy may be added later and is deliberately out of scope here.
- Feature 008 (Event Booking with Extra Services) builds its money paths on this rail and waits for this feature to land first.
- `offline-sync` (zero callers found during research) is deleted separately, contingent on roadmap confirmation.
