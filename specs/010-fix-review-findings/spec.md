# Feature Specification: Review Findings Remediation

**Feature Branch**: `010-fix-review-findings`

**Created**: 2026-08-21

**Status**: Draft

**Input**: "create a plan to fix that" — remediation of the 2026-08-21 full-project review (Standards axis: 3 HIGH / 7 MED / 5 LOW; Spec axis: commit hygiene + doc drift; Architecture axis: candidates #1–#6).

## Context

A two-axis review of `main` @ `bab9bc9` verified, against source files: payment-boundary violations in edge functions, an ownership-check gap in a state RPC, runtime-message leaks in error payloads, a live service-role credential committed in browser tooling, a dead RPC call in admin login, stale engineering docs, and a missing write seam in the admin app. Every finding below was verified with file:line evidence; this spec exists to close them before feature 008 builds new money paths and new booking screens on top of the same seams.

## Clarifications

### Session 2026-08-21

- Q: Which browser test harness should survive the consolidation? → A: Keep `test-apps/`, delete `test_portal/`.
- Q: How much of the existing admin app does the repository-seam refactor cover now? → A: All existing admin features, before 008 UI work begins.
- Q: What happens to portal workflows that needed the privileged client? → A: Re-authenticate all of them with seeded role accounts; manual verification only where genuinely impossible.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Payment writes go through one sanctioned seam (Priority: P1)

Today four code paths bypass the locked money boundary: the Paymob webhook inserts/updates `payments` rows directly, the shared Paymob helper updates them directly, checkout creates payment rows directly, and the nightly reconcile job marks payments failed directly. Separately, the newest payment RPC lets any authenticated caller skip the ownership check by passing a specific action value, meaning one member could advance another member's booking. A stakeholder reviewing this system should find exactly one doorway into payment state — everything else is closed.

**Why this priority**: Money is affected. The refund/race semantics (stale or cancelled bookings must land in refund-pending, never grant a seat) are only enforced inside the sanctioned RPCs; every direct write is a path around those guarantees.

**Independent Test**: An automated audit of integration code finds zero direct table writes to payments outside the RPC-calling module, and a transactional SQL test proves a non-owner cannot advance someone else's booking.

**Acceptance Scenarios**:

1. **Given** the hardened integration layer, **When** any of webhook, checkout, or reconcile handles a payment event, **Then** the resulting payment change happens inside a SECURITY DEFINER RPC, never as a direct table write.
2. **Given** a booking owned by member A, **When** member B attempts to advance it through the payment-recording path, **Then** the attempt is rejected and zero rows change.
3. **Given** the fix ships, **When** applied to an environment already at migration 0063, **Then** it arrives as a new forward migration with its own registered test — 0063 itself is never edited.

---

### User Story 2 - Error responses leak nothing (Priority: P1)

Two integration surfaces echo internal failure text back to callers: the shared HTTP helper copies token-error messages from the auth library into the response body, and the OTP function echoes raw exception text and upstream provider bodies. The frozen contract says clients see a machine code plus a catalog Arabic sentence — nothing else.

**Why this priority**: Runtime messages expose internals (library names, upstream payloads) and break the frozen Arabic error contract that both apps rely on for display.

**Independent Test**: Forcing each failure mode (bad token, expired session, upstream SMS failure) returns a body containing exactly a frozen code and a catalog Arabic sentence, with no library or provider text present.

**Acceptance Scenarios**:

1. **Given** an expired or malformed bearer token on any protected endpoint, **When** the response is produced, **Then** the body contains the frozen unauthorized code and its catalog Arabic sentence, and no substring of the underlying library message.
2. **Given** the SMS upstream fails or returns an error body, **When** the OTP endpoint responds, **Then** no raw exception text or provider payload appears in the response.
3. **Given** all endpoints, **When** their test suites run, **Then** each asserts absence of leaked messages, not just presence of a code.

---

### User Story 3 - No credentials in browser-served tooling (Priority: P1)

The local browser test portal embeds a service-role key literal in client-side script and hardcodes a known password across five files. It binds to loopback today, but the credential pattern violates Security-by-Default: zero credential literals in code. Anyone copying the portal pattern to a reachable host would silently bypass every protection policy.

**Why this priority**: A committed credential is a standing violation regardless of current reachability; the fix must make the safe pattern the only pattern.

**Independent Test**: A repository-wide scan for credential literals returns zero hits, and every portal workflow still completes using seeded role accounts through the normal anonymous-key client.

**Acceptance Scenarios**:

1. **Given** the remediated tooling, **When** the repository is scanned for embedded service-role secrets and hardcoded passwords, **Then** zero matches are found.
2. **Given** a tester opens each portal page, **When** they sign in with a seeded account for a role, **Then** every previously working workflow still works without any privileged client.
3. **Given** a workflow that genuinely required privileged access and has no unprivileged equivalent, **When** no safe pattern exists, **Then** that workflow is moved to documented manual verification rather than kept on a privileged browser client.

---

### User Story 4 - Admin login stops calling a deleted function (Priority: P2)

The admin identity flow still requests a server function that a recent migration removed. Every login therefore fires one guaranteed failed request, silently swallowed so the fallback role lookup can proceed. The result works but lies: it doubles login latency, logs noise errors forever, and tells the next reader the removed abstraction still exists.

**Why this priority**: No user is blocked — the fallback carries the decision — but the dead call contradicts the completed removal work and hides a silent-failure pattern.

**Independent Test**: Signing in as an allowed admin produces exactly the role-lookup request and no request to the removed function; signing in as a regular member is denied identically to today.

**Acceptance Scenarios**:

1. **Given** an allowed admin signs in, **When** the identity check completes, **Then** no request was made to the removed priest-inclusive function and access succeeds via the role lookup alone.
2. **Given** a USER-role member signs in, **When** the identity check runs, **Then** access is denied with the same Arabic messaging as before.
3. **Given** the identity flow code, **When** reviewed, **Then** no catch block swallows an error to fall through to another path — each branch's outcome is explicit.

---

### User Story 5 - Engineering documents match the shipped schema (Priority: P2)

The conventions document still lists enum values the database replaced months ago (slot status values differ; waiting-list values differ; the role list lacks the super-admin tier), and the agent handbook's admin role guard still names a priest tier the schema no longer contains. The next feature will be planned from these documents; stale values guarantee invented transitions that fail tests.

**Why this priority**: Documentation-only, but it actively misdirects planning — the same class of defect spec 009 had to clean up for the constitution.

**Independent Test**: Diffing each documented enumeration against the database's actual types yields zero differences, and the handbook role guard lists exactly the tiers that exist.

**Acceptance Scenarios**:

1. **Given** the synced conventions document, **When** its enumeration tables are compared to the live type definitions, **Then** every value matches and none were invented.
2. **Given** the handbook's admin route guard rule, **When** read against the shipped role set, **Then** it names exactly the existing administrative tiers.
3. **Given** future readers, **When** they consult either document, **Then** a pointer to the removal decision explains why the old tier is gone.

---

### User Story 6 - Admin screens stop touching the database directly (Priority: P3)

The mobile app keeps every network call behind per-feature repositories; the admin app does not: dozens of widget files issue queries and procedure calls inline, several through dynamically-typed handles. Schema renames fan out into screen edits, and the project's own testing rules (exercise the real repository, never private helpers) are unenforceable there.

**Why this priority**: Structural, not behavioral — but feature 008 adds admin booking screens next; landing the seam first means new screens start deep instead of adding leak sites.

**Independent Test**: A source scan of admin feature screens finds zero direct client calls; each feature's behavior is covered by tests exercising its repository.

**Acceptance Scenarios**:

1. **Given** the refactored admin app, **When** feature screens are scanned for direct data-layer calls, **Then** zero are found outside repository modules.
2. **Given** any admin feature, **When** its tests run, **Then** they exercise the real repository class against fakes, per project testing rules.
3. **Given** the refactor, **When** the full admin test suite and analysis gate run, **Then** all pass with Arabic strings and visible behavior unchanged.

---

### User Story 7 - One browser test suite, not two (Priority: P3)

The last commit added two parallel browser harnesses serving the same purpose — user, admin, super-admin flows — with duplicated helper logic between and within them. Neither is product code; keeping both doubles maintenance and guarantees drift.

**Why this priority**: Pure tooling hygiene; no product behavior changes.

**Independent Test**: Exactly one harness directory exists, it serves all role flows, and the other is gone from the repository.

**Acceptance Scenarios**:

1. **Given** the consolidated tooling, **When** a maintainer looks for the browser harness, **Then** exactly one suite exists covering all three roles.
2. **Given** the surviving suite, **When** its shared helpers are inspected, **Then** authentication/request/toast logic exists once, not per page.

### Edge Cases

- What if fixing the payment RPC's ownership gap breaks the legitimate flow where the paying owner records their own payment? The forward migration must keep owner-initiated recording working while closing the cross-user hole; the test pair proves both directions.
- What if removing the portal's privileged client breaks a super-admin-only screen? That screen moves to documented manual verification (or seeded-account flow) — it must not keep a secret to keep working.
- What if documentation sync tempts inventing enum values to "complete" a list? Only values present in the shipped types may be documented; absence is noted as an open question, never filled.
- What if the admin repository refactor touches screens mid-flight in another branch? Refactor is behavior-preserving; any bug spotted during it gets flagged separately, never bundled.
- What if a leak fix needs a new Arabic sentence? Catalog entries are data-editable; codes stay frozen at the existing five.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: All payment record creation and status changes performed by integration code MUST execute inside SECURITY DEFINER procedures; direct table writes to payments from integration code MUST be eliminated.
- **FR-002**: The payment-recording procedure MUST permit advancement only for the booking's owner or authorized staff, for every action path including the apply-payment path.
- **FR-003**: The FR-002 fix MUST ship as a new forward migration paired with a registered transactional test proving both denial (non-owner, zero rows) and allowance (owner proceeds).
- **FR-004**: Protected-endpoint error responses MUST contain only a frozen code and a catalog Arabic sentence; embedding library, exception, or upstream text MUST be removed.
- **FR-005**: Every integration endpoint's test suite MUST include an assertion that failure bodies contain no leaked internal messages.
- **FR-006**: Browser-served tooling MUST contain zero credential literals (service keys, passwords); privileged operations MUST use seeded role accounts over the normal public client or move to documented manual steps.
- **FR-007**: The admin identity flow MUST NOT call functions that no longer exist, MUST NOT swallow errors to fall through between branches, and MUST decide access solely from the stored role.
- **FR-008**: The conventions document's enumeration section MUST equal the shipped type definitions value-for-value, with a pointer to the governing decision where a value was deliberately retired.
- **FR-009**: The handbook's admin route-guard rule MUST name exactly the administrative tiers that exist in the shipped role set.
- **FR-010**: Admin feature screens MUST NOT issue direct data-layer calls; each feature MUST expose its behavior through a typed repository interface consumed by controllers.
- **FR-011**: Admin repositories MUST return typed success/failure results with internal exceptions mapped at the boundary, matching the mobile app's established seam shape.
- **FR-012**: Existing admin behaviors, Arabic strings, and routes MUST be preserved by the refactor; widget tests updated, never deleted to pass.
- **FR-013**: Exactly one browser test suite MUST exist — `test-apps/`; `test_portal/` MUST be removed from the repository; shared helper logic MUST exist once.
- **FR-014**: Every remediation touching applied migrations MUST obey forward-only rules (new numbered migration + registered test; no in-place edits).
- **FR-015**: Cross-cutting fixes in integration code MUST land in the shared modules (thin handlers, one seam per concern); duplication introduced by the fix counts as a regression.
- **FR-016**: Each remediation area MUST be independently committable (`fix(scope):`/`refactor(scope):`) so partial merges leave the tree green.

### Key Entities *(include if feature involves data)*

- **Payments**: financial rows whose entire write surface collapses to the sanctioned procedures; no new columns or statuses — privilege and call-path changes only.
- **Error catalog**: existing Arabic sentence catalog reused verbatim; no new codes beyond the frozen five.
- **Stored role**: single source of truth for admin access decisions; the removed priest-era function has no replacement — the role check IS the seam.
- **Documentation artifacts**: conventions enumerations and handbook guard rule treated as projections of the live schema, required to diff clean.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Automated audit reports zero direct payment-table writes in integration code outside the RPC-calling module (currently 4+ sites).
- **SC-002**: A non-owner advancing another member's booking through the payment path is denied with zero rows changed, proven by a passing registered test.
- **SC-003**: Forced-failure responses across all endpoints contain zero library/exception/upstream substrings, asserted by tests (currently 3 leaking sites).
- **SC-004**: Repository-wide credential scan returns zero literals (currently 1 service key + 5 password constants).
- **SC-005**: Admin sign-in performs exactly one identity round-trip with zero requests to nonexistent functions (currently a guaranteed failing call on every login).
- **SC-006**: Documented enumerations diff empty against shipped types (currently 3 divergent lists).
- **SC-007**: Admin feature-screen direct-call count equals zero (currently 30+).
- **SC-008**: Browser harness directory count equals one (currently 2).
- **SC-009**: All gates green after remediation: full SQL suite passes with parsed assertion output, integration unit suites pass, both apps' analyze-and-test gates pass.
- **SC-010**: Every fix lands on main as its own logical commit referencing the review finding it closes.

## Assumptions

- The committed service key is the well-known local demo credential; removal is about enforcing the zero-literals rule and safe reuse of the portal pattern, not about rotating a production secret.
- Portal tooling remains a localhost development aid; it is not shipped, deployed, or exposed beyond loopback.
- Consolidation keeps `test-apps/` and removes `test_portal/` (owner-confirmed 2026-08-21).
- Remediation lands before feature 008 implementation begins, so 008 builds on the fixed seams.
- No production data repair is required: all changes are privilege, call-path, code-shape, and documentation changes.
- The speculative idempotency-column concern (booking notes parsing) is out of scope here; it belongs to feature 008's schema work.
