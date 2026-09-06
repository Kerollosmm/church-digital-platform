# Feature Specification: Edge-Function Shared Kernel (Auth, Errors, Payment Gateway)

**Feature Branch**: `003-edge-function-kernel`

**Created**: 2026-08-16

**Status**: Draft

**Input**: User description: "Implement the top recommendation of the 2026-08-16 architecture review: one shared auth + response seam for all edge functions, and one shared payment-gateway adapter — eliminating 4 divergent bearer-auth gates (one of which never verifies the token), 3 byte-identical copies of the Paymob token exchange, 3 error-response dialects, and an 8× duplicated failed-payment cleanup block."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Every protected request is genuinely verified (Priority: P1)

A parishioner uses the mobile app. Every request they send to a protected backend endpoint (checkout, offline sync, analytics export, diagnostics, video purchase) must pass through the same identity verification before any business logic runs. Today one endpoint family only checks that a header *looks like* a token and never verifies it; others verify differently or return different rejections. After this feature, an attacker replaying a crafted or expired token gets the same rejection everywhere, and a genuine user gets through everywhere.

**Why this priority**: This is a live security defect class, not a convenience issue. Inconsistent verification means one weak endpoint undermines all strong ones. Nothing else in this feature matters if identity verification remains heterogeneous.

**Independent Test**: Send (a) no token, (b) malformed token, (c) expired token, (d) valid token to every protected endpoint and assert identical accept/reject behavior. Deliverable value: uniform access control, verifiable with a single penetration-style script.

**Acceptance Scenarios**:

1. **Given** a protected endpoint, **When** a request arrives with no credentials or a non-bearer scheme, **Then** it is rejected with the standard "unauthorized" error code and no business logic executes.
2. **Given** a protected endpoint, **When** a request arrives with a well-formed but invalid or expired token, **Then** it is rejected with the standard "unauthorized" error code.
3. **Given** a protected endpoint, **When** a request arrives with a valid token, **Then** the caller's identity is established and passed to the business logic exactly once.
4. **Given** an endpoint restricted to church staff roles, **When** a valid token belonging to a non-staff user arrives, **Then** it is rejected with the standard "forbidden" error code.
5. **Given** an endpoint that receives webhooks from the payment provider, **When** a request arrives, **Then** it is authenticated by the provider's message signature instead of user tokens, and user tokens grant nothing there.

---

### User Story 2 - One error contract clients can rely on (Priority: P2)

The mobile app and admin web app consume backend errors to show Arabic/English user messages and drive retry buttons. Today the backend answers in three JSON dialects and occasionally plain text, so clients string-match and miss cases. After this feature, every failure anywhere in the backend surface returns one machine-readable error format with stable codes, letting the clients map codes to messages once.

**Why this priority**: Directly blocks client-side error handling work; every app feature that calls the backend inherits this contract. Second only to auth correctness because wrong error shapes confuse users but do not open security holes.

**Independent Test**: Trigger each error class (unauthorized, forbidden, bad request, upstream payment provider failure, internal error) against representative endpoints and assert one format and one code vocabulary throughout.

**Acceptance Scenarios**:

1. **Given** any backend endpoint, **When** any handled failure occurs, **Then** the response body uses the single agreed error format with a stable machine-readable code.
2. **Given** an internal unexpected failure, **Then** the response reveals no internal details (stack traces, SQL, provider payloads) while the failure is fully logged server-side.
3. **Given** a pre-flight cross-origin request, **When** it arrives, **Then** it receives the standard cross-origin headers shared by all endpoints.

---

### User Story 3 - Payment operations flow through one gateway path (Priority: P3)

A church admin reconciles payments and issues refunds. Today the payment gateway token exchange is copy-pasted in three places, refund processing performs database writes and gateway calls inline inside the event dispatcher, and the end-to-end script re-implements the webhook signature field list — so a gateway protocol fix must be applied up to five times and drift breaks reconciliation silently. After this feature, every gateway interaction (authenticate, checkout, refund, transaction status) flows through one shared integration, and failure handling (mark payment failed, surface gateway error, no silent fallbacks) is defined once.

**Why this priority**: Consolidates the highest-volume duplication found by the review. Ranked below auth and error contract because current duplication is operationally expensive but currently functioning.

**Independent Test**: Induce gateway failures (timeout, invalid payload, malformed response) at each call site and assert identical failure outcomes: payment marked failed, gateway-error response returned to caller, incident logged. Assert the gateway signature field list is defined exactly once and reused by the end-to-end script.

**Acceptance Scenarios**:

1. **Given** any flow needing a gateway session token, **When** the gateway returns an error or unparseable response, **Then** the flow fails visibly with the standard gateway-error code instead of proceeding half-authenticated.
2. **Given** a payment that fails after being recorded, **When** cleanup runs, **Then** the payment is marked failed through one shared cleanup behavior (not per-call-site copies).
3. **Given** the event dispatcher processing a refund, **When** the gateway refund call fails, **Then** the refund remains queued for retry/review and the failure is logged; it never silently drops.
4. **Given** the outbox claim mechanism, **When** its atomic claim call fails, **Then** the run aborts loudly with an incident log — it must not silently fall back to a non-atomic claim that can double-send messages.

---

### User Story 4 - New backend functions are safe by default (Priority: P4)

A developer adds a new edge function. Today they must hand-copy auth, CORS, and error shaping from a sibling and pick which of four dialects to copy — the empty shared test directory shows the intended seam was never delivered. After this feature, the developer composes the shared auth and response behaviors, and the platform's automated tests verify the shared paths once for all functions.

**Why this priority**: Multiplies the value of every future feature; ranked last because it pays forward rather than fixing today's defects.

**Independent Test**: Confirm automated tests cover the shared auth and gateway behaviors with fake dependencies, and that the shared test directory is no longer empty.

**Acceptance Scenarios**:

1. **Given** the shared authentication behavior, **When** its automated suite runs, **Then** all verification outcomes (valid, missing, malformed, expired, insufficient role) are asserted.
2. **Given** the shared gateway integration, **When** its automated suite runs, **Then** success, protocol failure, and unparseable-response paths are asserted with a fake gateway.
3. **Given** any new function, **When** it is built from the shared behaviors, **Then** it contains zero copies of token-exchange, verification, or error-shaping logic.

---

### Edge Cases

- Token structurally valid but belonging to a deleted/absent user account: request must be rejected as unauthorized, not fall through (related NULL-role bypass fix is a prerequisite, see Assumptions).
- Credentials missing from the environment at function startup: the function must fail loudly; it must never substitute placeholder or fallback credentials (the "test" HMAC key and anon-key fallbacks found in review are removed as a prerequisite).
- Upstream gateway returns HTTP 200 with malformed JSON: treated as gateway failure, not success.
- Concurrent runs of the event dispatcher when the atomic claim is unavailable: the run must abort rather than degrade to duplicate-prone claiming.
- Cross-origin pre-flight (OPTIONS) requests: handled by the shared behavior before auth, so anonymous pre-flights succeed.
- Webhook replay with a valid signature but duplicate transaction: idempotency preserved (existing behavior; must survive the consolidation unchanged).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Every endpoint that serves application clients MUST verify the caller's bearer token against the identity provider before executing any business logic, and MUST reject unverified requests with the standard unauthorized error code.
- **FR-002**: Role-restricted endpoints MUST additionally verify the caller's role from trusted account metadata and reject insufficient roles with the standard forbidden error code.
- **FR-003**: Endpoints receiving payment-provider webhooks MUST authenticate via the provider's message signature and MUST NOT accept or privilege user tokens.
- **FR-004**: All error responses across all endpoints MUST use a single machine-readable format with a stable, documented code vocabulary (at minimum: unauthorized, forbidden, bad request, upstream gateway error, internal error).
- **FR-005**: Unexpected internal failures MUST be logged server-side with diagnostic detail and MUST NOT leak internal details to clients.
- **FR-006**: All payment-gateway interactions (session authentication, checkout, refund, transaction status) MUST flow through one shared integration with a single implementation of retry, timeout, and unparseable-response handling.
- **FR-007**: When the payment gateway fails or returns an unparseable response, the system MUST mark the affected payment failed, return the upstream gateway error code to the caller, and log the incident.
- **FR-008**: A payment recorded but not completed MUST be marked failed through one shared cleanup behavior rather than per-flow copies.
- **FR-009**: The outbox claim mechanism MUST abort its run with an incident log when its atomic claim call fails; silent fallback to non-atomic claiming MUST NOT occur.
- **FR-010**: All credentials and secrets MUST be read from the deployment environment; missing credentials MUST cause a loud startup failure. Hardcoded credential fallbacks MUST NOT exist anywhere in the codebase.
- **FR-011**: The shared authentication and gateway behaviors MUST be covered by automated tests using fake identity/gateway dependencies, covering valid, missing, malformed, expired, and insufficient-role cases.
- **FR-012**: Cross-origin pre-flight handling MUST be provided by the shared behavior and applied uniformly across endpoints.
- **FR-013**: The behavior-consolidation MUST preserve all existing externally visible successes (successful checkout, webhook idempotency, offline sync results, refund queueing) unchanged — this is a behavior-preserving consolidation, not a redesign.

### Key Entities *(include if feature involves data)*

- **Protected Endpoint**: A backend endpoint serving app clients; characterized by its required role level; all share one verification behavior.
- **Webhook Endpoint**: A backend endpoint receiving signed events from the payment provider; authenticated by signature, mutually exclusive with user-token auth.
- **Error Code**: A stable machine-readable failure identifier from one vocabulary, mapped by clients to user-facing messages.
- **Gateway Operation**: A category of payment-provider interaction (authenticate, checkout, refund, status); all instances share one failure policy.
- **Outbox Lease**: The exclusive right, granted atomically, for one run to process a batch of queued messages; loss of atomicity aborts the run.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of protected endpoints reject missing, malformed, and expired tokens with the standard unauthorized code (verified by an automated sweep across every endpoint — zero exceptions).
- **SC-002**: Zero error-response dialects remain: every endpoint's failure responses conform to the single format (verified by a response-format audit across all endpoints; today there are at least three dialects plus one plain-text response).
- **SC-003**: Payment-gateway session logic exists in exactly one place (today: three identical copies), and the webhook signature field list is defined once and reused by the end-to-end script (today: two divergent definitions).
- **SC-004**: The shared auth and gateway behaviors have automated tests for all verification outcomes and gateway failure modes; the shared test directory contains suites (today: empty).
- **SC-005**: An automated credential scan of the repository finds zero hardcoded secrets, URLs-with-keys, or fallback credential values.
- **SC-006**: All existing SQL regression suites and end-to-end payment flow pass unchanged after consolidation (behavior-preserving).

## Assumptions

- The three commit blockers identified by the 2026-08-16 architecture review land **before** this feature: (1) removal of hardcoded credential fallbacks in the diagnostic engine script, (2) reverting the in-place edit of applied storage migration 0044 into a forward migration, (3) the NULL-role bypass fix and missing privilege revocation in the video-purchase function. This feature depends on them but does not include them.
- Scope is the existing edge-function surface (9 functions); no new endpoints are added.
- The payment provider (Paymob) and its integration protocol remain unchanged; this is consolidation, not provider migration.
- Refund processing remains a manually-actioned administrative queue (ADR 0001: no automated refund API calls); moving refund state transitions into a database routine (review candidate #4) is a separate future feature.
- Giving the diagnostic engine a testable dependency seam (review candidate #5) is out of scope beyond its credential cleanup; it will adopt the shared seam in a later feature.
- The mobile/admin clients will map the unified error codes to user-facing messages in their own follow-up work; the code vocabulary is documented as part of this feature.
- Booking state machine consolidation (review candidate #3) is out of scope.
