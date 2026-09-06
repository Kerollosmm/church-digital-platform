# Feature Specification: Egyptian Coptic Orthodox Church Digital Platform UI & Continuous Discovery System

**Feature Branch**: `001-church-platform-ui`  
**Created**: 2026-08-14  
**Last Updated**: 2026-08-14 (Post-Clarification)  
**Status**: Ready for Planning (`/speckit-plan`)  
**Input**: User description: "use your skill /continuous-discovery-ux and /stitch to generate the UI for the app generate it not write the forntedn code on project just generate the ui and review it accourfiding to your rules and skill of ux deign loop"

---

## Clarifications

### Session 2026-08-14
- **Q1 (Family Seat Cap & Names):** What is the maximum seat cap per transaction and are individual attendee names mandatory?  
  $\to$ **A1:** Maximum **4 seats** per reservation; only the head-of-household (primary parishioner) name is captured alongside the total seat count.
- **Q2 (Admin PIN Recovery):** How is an admin account unlocked or a forgotten PIN reset?  
  $\to$ **A2:** **Self-Service OTP Reset**: Admin can reset their memorized PIN by re-authenticating via a fresh WhatsApp/SMS OTP challenge.
- **Q3 (Confession Cancellation Cutoff):** What is the cancellation cutoff window for Confession appointments?  
  $\to$ **A3:** Cancellations are permitted up to **2 hours** prior to the scheduled slot; released slots immediately reopen for booking by other parishioners.
- **Q4 (Offline Door Verification):** How are passes verified at church sanctuary doors with weak cellular connectivity?  
  $\to$ **A4:** **Offline Cached Pass**: The mobile app caches confirmed passes locally with an offline QR code and short 4-character entry verification code.
- **Q5 (Seasonal Liturgy Booking Limits):** Should the system enforce active booking limits per household for fair distribution?  
  $\to$ **A5:** **Seasonal Dynamic Cap**: Up to 2 active Mass bookings per household during normal weeks; automatically constrained to 1 active booking during designated Coptic feast seasons (Holy Week, Christmas, Easter).

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Parishioner Holy Mass Multi-Seat Reservation (Priority: P1)

Parishioners and families can open the mobile application, view upcoming liturgical Mass schedules, select a service with available capacity, choose up to 4 seats for their family, provide the head-of-household name in Arabic, and receive an instant booking confirmation pass cached for offline entry.

**Why this priority**: Holy Mass (القداس الإلهي) is the central weekly sacramental activity of the parish. Capacity enforcement and transparent multi-seat family reservation prevent overcrowding and eliminate manual in-person church registration bottlenecks.

**Independent Test**: Can be fully tested by selecting an upcoming Friday or Sunday Mass slot, specifying 3 family seats (head-of-household + 2), submitting the form, verifying capacity deduction, and viewing the cached digital pass with QR and 4-character code.

**Acceptance Scenarios**:

1. **Given** a parishioner is viewing the Liturgy schedule and a Mass has 12 available seats, **When** they select 3 seats, confirm the head-of-household name, and submit the booking, **Then** the booking is confirmed, 3 seats are deducted from total capacity, and a confirmation summary appears.
2. **Given** a parishioner attempts to book more than 4 seats in a single reservation, **Then** the seat stepper caps the selection at 4 seats.
3. **Given** a parishioner has 2 active Mass reservations in a normal week (or 1 during a designated Feast season), **When** they attempt to book an additional Mass, **Then** the system presents a polite fair-distribution notification explaining the active reservation limit.
4. **Given** a parishioner arrives at church with zero cellular connection, **When** they open their confirmed booking pass, **Then** the app renders the locally cached pass, scannable QR code, and 4-character verification code.

---

### User Story 2 - Confession Appointment Private Scheduling (Priority: P2)

Parishioners can browse the clergy directory, select their assigned Father of Confession (أب الاعتراف), view available 15-minute appointment slots, attach an optional encrypted spiritual note, and manage or cancel bookings up to 2 hours before the appointment.

**Why this priority**: Spiritual counseling and the Sacrament of Confession require absolute privacy, predictable scheduling, and avoidance of public church queueing friction.

**Independent Test**: Can be fully tested by selecting a priest, choosing a date and time slot (e.g., 5:15 PM), entering a private note, confirming the booking, and subsequently testing cancellation >2 hours before the start time to confirm the slot re-opens.

**Acceptance Scenarios**:

1. **Given** a parishioner selects their Father of Confession, **When** they select an open 15-minute slot and confirm, **Then** the slot is immediately locked for that parishioner and marked unavailable to others.
2. **Given** a parishioner with a confirmed confession slot cancels $\ge 2$ hours before the time, **Then** the appointment is cancelled and the slot immediately becomes available in the directory for other parishioners.
3. **Given** a parishioner attempts to cancel $< 2$ hours before the scheduled time, **Then** the app advises them that the cancellation window has closed and provides a direct church office contact.

---

### User Story 3 - Clergy & Church Admin Three-Factor Secure Access & PIN Reset (Priority: P1)

Church servants, administrators, and priests accessing the Admin Web Portal must undergo a 3-step security verification: (1) Mobile phone number entry, (2) One-Time Password (OTP) verification delivered via WhatsApp/SMS, and (3) A memorized 4–6 digit PIN verification (with first-run setup and self-service OTP PIN recovery).

**Why this priority**: Church administration terminals are frequently shared across volunteer shifts. Requiring a memorized second-factor PIN protects sensitive parish data, donation records, and confidential pastoral correspondence against unauthorized access if a terminal is left unattended.

**Independent Test**: Can be fully tested by entering an admin phone number, submitting a valid WhatsApp OTP code, entering the 6-digit memorized PIN, and testing the self-service OTP reset flow when "Forgot PIN" is triggered.

**Acceptance Scenarios**:

1. **Given** an admin user has verified their phone and OTP, **When** they enter their correct 6-digit PIN on the numeric keypad, **Then** they are granted access to the admin dashboard.
2. **Given** a newly registered servant logging in for the first time without a PIN, **When** they successfully pass OTP verification, **Then** the system directs them to a PIN Setup screen requiring PIN entry and confirmation.
3. **Given** an admin clicks "Forgot PIN" or is locked out after 5 invalid attempts, **When** they initiate a PIN reset, **Then** the system issues a fresh WhatsApp/SMS OTP challenge; upon successful verification, they are guided to establish a new memorized PIN.

---

### User Story 4 - Priest Emergency Schedule Override & Automated Reconciliation (Priority: P3)

A priest facing an urgent pastoral duty (e.g., emergency hospital visit or funeral prayer) can initiate an Emergency Override on a scheduled Mass or confession slot from the admin portal, instantly notifying affected parishioners and routing paid bookings to the refund review queue.

**Why this priority**: Clergy schedules must adapt to unpredictable pastoral emergencies while preserving parishioner trust through clear Arabic WhatsApp communication and financial integrity.

**Independent Test**: Can be fully tested by triggering an Emergency Override on an active liturgy slot with bookings, verifying that the slot status changes to "Cancelled/Emergency", automated cancellation notices are dispatched, and any associated paid transactions enter the refund queue.

**Acceptance Scenarios**:

1. **Given** an active liturgy slot with confirmed bookings, **When** the priest activates the Emergency Override with an explanation reason, **Then** all attendees receive an automated Arabic WhatsApp notification explaining the cancellation, and the slot is removed from the public booking directory.

---

### Edge Cases

- **Concurrent Last-Seat Contention**: Two parishioners attempting to book the final available seat simultaneously $\to$ The first submission to complete transactional reservation secures the seat; the second user receives an immediate polite message indicating the slot just filled up with an alternative date suggestion.
- **Door Verification Without Cellular Coverage**: Church sanctuary or basement has zero cellular reception $\to$ Door servants scan the locally cached QR code or manually verify the 4-character entry code against the synchronized on-site roster.
- **PIN Brute-Force Defense**: 5 consecutive incorrect PIN entries disable the keypad and transition the interface to the self-service WhatsApp OTP reset flow.
- **Fair Allocation Enforcement**: System tracks active bookings per mobile phone number; prevents exceeding 2 active bookings in standard weeks or 1 active booking during designated Feast periods.

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide an Arabic Right-to-Left (RTL) interface optimized with the Cairo font hierarchy across all mobile and web screens.
- **FR-002**: System MUST allow parishioners to browse Holy Mass schedules filterable by date, church altar, and officiating priest.
- **FR-003**: System MUST support multi-seat selection capped at a maximum of **4 seats per transaction** (head-of-household plus up to 3 family members).
- **FR-004**: System MUST capture the reserving head-of-household name in Arabic along with the total seat count for each reservation.
- **FR-005**: System MUST enforce an active Mass reservation limit per household of **2 active bookings** during regular weeks and **1 active booking** during designated Coptic feast seasons.
- **FR-006**: System MUST cache confirmed booking passes locally on the mobile device with an offline-scannable QR code and short 4-character verification entry code.
- **FR-007**: System MUST lock seat capacity for a configurable 20-minute reservation checkout window prior to final confirmation, automatically releasing unconfirmed seats upon expiry.
- **FR-008**: System MUST provide a private confession booking directory with priest availability segmented into 15-minute time increments.
- **FR-009**: System MUST permit parishioners to cancel confession appointments up to **2 hours prior** to the start time, immediately reopening the slot for other parishioners.
- **FR-010**: System MUST secure private counseling and confession notes with end-to-end privacy visible solely to the assigned priest.
- **FR-011**: System MUST enforce a three-step authentication sequence for admin web users: Phone Number $\to$ WhatsApp OTP $\to$ Memorized 4–6 Digit PIN.
- **FR-012**: System MUST provide a first-run PIN setup interface with confirmation matching for uninitialized admin accounts.
- **FR-013**: System MUST provide a self-service PIN Reset flow triggered via WhatsApp/SMS OTP re-verification for forgotten PINs or account lockouts.
- **FR-014**: System MUST provide an Admin Dashboard with real-time KPI metrics (Total Seats Reserved, Occupancy Rate %, Pending Refund Requests, Confessions Count).
- **FR-015**: System MUST provide a Priest Emergency Override capability that cancels a slot, triggers automated notifications, and logs refund queue entries.
- **FR-016**: System MUST adhere to 100% 5-State UI coverage (Ideal, Empty, Loading Skeleton, Error with Retry, and Partial/Lockout states) across all interactive views.
- **FR-017**: System MUST utilize structured shimmer skeleton loaders matching final card geometry and prohibit generic centered loading spinners.

---

### Key Entities

- **Parishioner / User**: Represents a church community member with full name, verified Egyptian mobile number, active booking count, and role permissions.
- **Service Slot (Liturgy / Mass)**: A scheduled sacramental gathering with date, start/end time, capacity ceiling, remaining seats, season type (Regular vs. Feast Season), officiating clergy, and current status.
- **Booking / Seat Reservation**: A confirmed ticket for 1 to 4 seats attached to a specific service slot, including head-of-household name, seat count, 4-character entry code, cached QR payload, and active state.
- **Confession Appointment**: A confidential 1-on-1 pastoral session linking a parishioner to a specific priest with designated time slot, cancellation cutoff timestamp, and private encrypted notes.
- **Admin PIN Credential**: A secure, hashed memorized 4–6 digit numeric secret associated with an administrative account, supporting OTP-driven reset and failed attempt counters.
- **Refund Queue Item**: An administrative tracking record created when a paid booking is cancelled or superseded by an emergency override.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Parishioners can complete a multi-seat Liturgy reservation in **under 45 seconds** from app launch.
- **SC-002**: Overall booking completion rate reaches or exceeds **92%** across all age cohorts (18–75).
- **SC-003**: 100% of confirmed mobile booking passes are viewable and scannable in **zero-connectivity / offline mode**.
- **SC-004**: Single Ease Question (SEQ) usability score averages **$\ge 6.0 / 7.0$** in user testing.
- **SC-005**: Zero unauthorized terminal access on shared church admin computers (**100% 3-Step PIN enforcement**).
- **SC-006**: Self-service PIN reset completion rate exceeds **95%** without requiring IT administrator support tickets.
- **SC-007**: Clergy can execute an Emergency Slot Override and trigger automated parishioner alerts in **under 3 clicks**.
- **SC-008**: 100% of screens exhibit zero Content Layout Shift (CLS $\le 0.05$) by employing structured layout-matching skeleton loaders.
- **SC-009**: Church administrative phone and office queueing volume decreases by at least **45%** within 60 days of release.

---

## Assumptions

- **Language & Locale**: The primary operating language is Egyptian Arabic (RTL), with standard Gregorian and Coptic liturgical calendar references.
- **Network Resilience**: Parishioners may experience intermittent connectivity in church sanctuaries; all transactional actions provide local pass caching, clear offline messaging, and inline retry capabilities.
- **Communication Channels**: Official transactional reminders and OTP codes are delivered primarily through approved WhatsApp templates with SMS fallback.
- **Security Scope**: Administrative PIN verification protects client-side application state and validates against secure backend access boundaries without exposing credentials in client storage.