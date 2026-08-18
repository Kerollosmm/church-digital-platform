# Feature Specification: Accessibility Foundations — Alt Text, Personal Video Delivery, Localized Errors

**Feature Branch**: `004-accessibility-foundations`

**Created**: 2026-08-16

**Status**: Draft

**Input**: User description: "Close the backend's top accessibility gaps found by the 2026-08-16 WCAG 2.1 AA audit: (1) no alt-text storage for any published image, (2) no automated delivery of personal event videos to the booking holder's phone, (3) error contract is English-only. Add the missing storage, delivery automation, and localization so blind and elderly Arabic users can actually use the platform." (Revised 2026-08-17 after owner interview — see Clarifications Session 2026-08-17; caption enforcement removed by owner decision.)

## Clarifications

### Session 2026-08-16

- Q: Should image text alternatives live in one central media table shared by announcements, priest profiles, and church media, or as separate columns on each content table? → A: One central `media_assets` table (alt text, decorative flag, language, tenant); content tables reference it.
- Q: Where should the publish-refusal for missing alt text / caption status be enforced? → A: In the publish/visibility SECURITY DEFINER RPCs (conventions-aligned), with RLS and privilege hardening preventing direct table-write bypasses.
- Q: How should edge functions deliver the Arabic error messages? → A: In-memory cache of the whole catalog per function instance with a short TTL (e.g. 5 minutes); lookup failure fails safe to the generic Arabic fallback.
- Q: Where should the legacy-video caption grace date live? → A (user clarification, reframing): Videos are not a public catalog — they are personal per-booking filming deliverables (e.g. baptism, wedding add-ons). Pay happens on site or online at/after booking; when staff marks the video ready, the buyer is notified on WhatsApp with an access link usable only by the booking's verified phone number. There is no on-sale catalog, so no legacy sale grace date is needed; the caption gate applies at mark-ready/delivery time, and pending deliverables appear in the staff backlog.
- Q: Should the staff backlog report paginate with a keyset cursor or offset paging? → A: Keyset cursor on (created_at, id) — stable under concurrent repairs, constant-time deep pages.

### Session 2026-08-17

Owner interview (Arabic) — product-level corrections:

- Q: Are videos one type or two? → A: Two types. **Global videos**: public catalog entries — external YouTube links (navigate to YouTube, never embedded), each free or paid (per-video choice; paid via Paymob). **Personal videos**: per-booking filming deliverables — staff enters the person's phone number + YouTube link + title in admin, and the system automatically sends the link via WhatsApp to that number.
- Q: Are captions required on personal videos? → A: No. A video carries a **title only** — no caption/transcript metadata, no delivery gate. Caption enforcement removed from this spec by owner decision (may return as a future feature if an audit requires it).
- Q: How is payment handled? → A: All payments run through Paymob, which supports local purchase methods (electronic wallets المحافظ الإلكترونية and Visa).
- Q: What does "verified number" mean? → A: Bookings are made with a phone number so an official can call to confirm the booking; that number is already in the system and is the delivery channel for the personal video.
- Q: One church or many? → A: One church only. Tenant scaffolding stays as-is (cheap, locked repo pattern) but is not exposed anywhere.
- Q: Work ordering conflicts? → A: Owner has none — reviewer manages order: merge 003 → implement 004 → 005.
- Note (owner, 2026-08-17): The confirmation call is mandatory — a booking stays "in progress" (`AWAITING_CALL`, already in the 0008/0024 state machine) until an admin user confirms it after calling, like processing an order. This feature assumes it: `deliver_personal_video` requires a PAID payment, which only exists on the confirmed path. The confirmation queue UI (list `AWAITING_CALL` + confirm button → `transition_booking_status`) belongs to 005-admin-domain-layer.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Blind parishioner hears what the images show (Priority: P1)

A blind parishioner uses the mobile app with a screen reader (Arabic TTS). Today every announcement photo, priest portrait, and church media image announces as unnamed "image" because the backend stores no text alternative — the screen reader cannot describe what the database never recorded. After this feature, every newly published image carries a short Arabic description the client can announce, and church staff cannot publish an image without one.

**Why this priority**: Complete blocker for non-visual access to the Community & Parish Info pillar; every screen with imagery is affected. One-time storage + enforcement fix with permanent effect.

**Independent Test**: Query the content APIs — every published image record returns a non-empty description; an attempt to publish an image without one is refused. Screen-reader walkthrough of the announcements screen announces descriptions.

**Acceptance Scenarios**:

1. **Given** a church staff member publishes an announcement with an image, **When** the image is saved without a text description, **Then** the publish is refused with a clear validation error identifying the missing description.
2. **Given** any published announcement, priest profile, or media item with an image, **When** the parishioner's app requests it, **Then** the record includes a non-empty text alternative suitable for screen-reader announcement.
3. **Given** an image that is purely decorative, **When** it is saved, **Then** it can be explicitly marked decorative so screen readers skip it (empty-by-design, not missing).
4. **Given** content published before this feature (legacy images with no description), **When** staff opens the content manager, **Then** a backlog list of undescribed images is available for gradual repair — legacy content is not hidden from users while repairs happen.

---

### User Story 2 - Booking holder receives his personal video automatically (Priority: P2)

A parishioner books an event (baptism معمودية, wedding فرح) with a phone number — an official calls to confirm, so the number is already in the system. Filming is a paid add-on (Paymob: wallets or Visa). After the event, staff enters in admin: the person's phone number, the YouTube link, and a title — title is the only metadata. The system then automatically links the video to that person, grants access, and sends the YouTube link to their WhatsApp. No manual copy-paste, no forgotten promises. General church event videos are a separate public catalog — free or paid per video — whose links open on YouTube directly; personal videos never appear in that catalog.

**Why this priority**: The church promises "the video will reach you" at payment time; today delivery depends on staff remembering to WhatsApp each buyer. Automation removes the failure mode for (often elderly) users whose only channel is WhatsApp.

**Independent Test**: Call the delivery entry point with phone + YouTube URL + title linked to a PAID payment — video created (unlisted, title set), access granted to that user, one WhatsApp outbox event queued with the buyer's number. Unknown phone number → refused loudly.

**Acceptance Scenarios**:

1. **Given** a PAID filming payment, **When** staff submits phone + YouTube link + title, **Then** an unlisted video is created, linked to the user with that exact phone, access is granted, and a WhatsApp link message is queued to that number.
2. **Given** a phone number that matches no user, **When** staff submits it, **Then** the delivery is refused with `UNKNOWN_PHONE` and nothing is sent (no wrong-number WhatsApp).
3. **Given** a global (catalog) video, **When** staff publishes it, **Then** it is free or paid per its price (paid → existing Paymob checkout) and its link navigates to YouTube externally; it never appears as anyone's personal deliverable.
4. **Given** staff retries a delivery for a purchase that already has access granted, **Then** the submission is idempotent — no duplicate video, no duplicate WhatsApp message.

---

### User Story 3 - Elderly Arabic user meets errors in Arabic (Priority: P3)

An elderly, low-vision Arabic user relies on large text and text-to-speech. Today every backend failure speaks English jargon ("UNAUTHORIZED", "UPSTREAM_ERROR") — correct for machines, meaningless to her. After this feature, every client-facing error pairs its stable machine code with a maintained, centrally-editable Arabic human message the client can display or announce verbatim.

**Why this priority**: Universal-communications polish riding the existing unified error contract; wrong-language errors confuse but rarely block (users retry anyway).

**Independent Test**: Trigger representative errors (unauthorized, forbidden, bad request, upstream, internal) — each response includes a non-empty Arabic message; messages are editable without code changes.

**Acceptance Scenarios**:

1. **Given** any client-facing error from any endpoint, **When** the response is formed, **Then** it contains the stable machine code and a non-empty Arabic human-readable message.
2. **Given** the church wants to reword a message, **When** an editor updates the catalog, **Then** new responses use the new wording without any code deployment.
3. **Given** a screen-reader user, **When** an error occurs, **Then** the announced text is the Arabic message, not the machine code.

---

### Edge Cases

- Decorative images: marked decorative → screen readers skip; must be distinguishable from "missing description" in the backlog.
- Mixed-script descriptions (Arabic + Coptic terms): stored and served as-is; announcement quality is a content-editing concern, not enforced by the backend.
- Wrong phone number typed by staff: delivery refuses unknown numbers (`UNKNOWN_PHONE`) — staff confirms the number rather than the system guessing; near-miss numbers never receive a WhatsApp link.
- Buyer loses or changes phone: video access stays bound to the original user record; re-binding is a manual admin action, not self-service.
- Duplicate delivery submissions (staff double-click / retry): idempotent — no second video, no second WhatsApp message.
- Very long error messages under TTS: catalog guidance keeps messages one short sentence; length not hard-enforced.
- Legacy content flood: backlog query must paginate; repair is gradual, publish-blocking applies to new content only.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST store a text alternative for every published image across announcements, priest profiles, and church media, alongside a flag distinguishing decorative images from undescribed ones.
- **FR-002**: The system MUST refuse publishing (making visible to parishioners) any new image-bearing content whose image lacks a non-empty text alternative or the decorative flag. Enforcement lives in the publish/visibility SECURITY DEFINER RPC; RLS plus privilege-hardened grants leave no direct table-write bypass.
- **FR-003**: Text alternatives MUST accept and preserve Arabic text as first-class content (no transliteration, no truncation).
- **FR-004**: The system MUST provide automated personal-video delivery: a staff entry point accepting the buyer's phone number, a YouTube URL, and a title (title is the only required video metadata — no caption or transcript fields exist). It MUST resolve the buyer by exact phone match (`users.phone`), refuse unknown numbers with `UNKNOWN_PHONE`, require the linked payment to be PAID, be idempotent on retry, and — on success — create the unlisted video, grant the buyer access, and enqueue exactly one WhatsApp outbox event carrying the YouTube link. Personal videos MUST NOT appear in the public catalog. (No caption gate exists — owner decision 2026-08-17.)
- **FR-005**: Video records exposed to buyers MUST include the title and the external YouTube URL only after access is granted. Global (catalog) videos carry a price (0 = free; paid → existing Paymob checkout) and open on YouTube externally.
- **FR-006**: The system MUST provide, for every client-facing error code in the unified error contract, a maintained Arabic human-readable message delivered alongside the machine code in the error response.
- **FR-007**: The error message catalog MUST be editable without code deployment (data-level change) and MUST fail safe to a generic Arabic message if a code has no catalog entry. Edge functions serve messages from an in-memory cache of the catalog with a short TTL (e.g. 5 minutes), so edits propagate without redeploy.
- **FR-008**: The system MUST provide a staff-facing backlog report of legacy content missing text alternatives, paginated by keyset cursor on (created_at, id) so concurrent repairs never skip or duplicate rows.
- **FR-009**: New tables/columns MUST follow existing multi-tenant patterns (tenant column with default, tenant-checked policies, explicit role targeting) and MUST NOT weaken any existing policy.
- **FR-010**: Behavior outside these additions MUST be unchanged (booking, payment, refunds, offline sync, existing content visibility for legacy items).
- **FR-011**: Restricted new functions MUST follow the privilege hardening pattern (revoke from PUBLIC/anon/authenticated before targeted grants) and MUST have negative-authorization tests.
- **FR-012**: All schema changes MUST be forward migrations; existing applied migrations MUST NOT be edited.

### Key Entities *(include if feature involves data)*

- **Media Asset / Media Alternative**: Central, content-agnostic record holding a published image's text alternative; attributes: text (Arabic-first), decorative flag, language, tenant, and a reference from the owning content item (announcement, priest profile, or church media). One table serves all three content types; the backlog report reads this single source.
- **Video Deliverable**: A personal unlisted YouTube video linked to a booking holder by exact phone match; metadata is a title only; delivery is an automated WhatsApp message (via the outbox) and never appears in the public catalog.
- **Global Video**: A public catalog video — external YouTube link, free or paid per its price (paid via Paymob wallets/Visa).
- **Localized Error Message**: Catalog entry mapping a stable error code to an Arabic human message; editable at data level; generic fallback entry for unknown codes.
- **Content Backlog**: Derived, paginated listing of legacy content missing text alternatives.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After cutover, a catalog query returns zero newly published image-bearing items lacking a text alternative or decorative flag (automated test).
- **SC-002**: Publishing an undescribed image or delivering a video to an unregistered phone is refused in 100% of attempted cases (automated tests, including staff-role attempts and tenancy edge cases).
- **SC-003**: Every code in the unified error contract returns a non-empty Arabic message in a sample call per code; an uncatalogued code returns the generic fallback (automated test).
- **SC-004**: The backlog report returns all known legacy offenders (count matches a one-time audit snapshot) and paginates (automated test).
- **SC-005**: All pre-existing SQL and function test suites pass unchanged.

## Assumptions

- Scope = audit findings #1 (alt text), personal video delivery automation, #5 (localized errors). Excluded for future features: user preference persistence, content language metadata, image size variants, slot-lock expiry surfacing, voice OTP.
- Client-side rendering (Flutter semantics, screen-reader announcement, caption player) is tracked as separate client work; this feature delivers the data and enforcement.
- Known image detection limitation: `publish_announcement` detects images via `body_ar` containing `announcement_images` and storage paths prefixed `ann{id}/` or `{id}/`. Images referenced by external URLs or stored under other path shapes are not detected by the gate and surface only in the backlog report.
- Videos carry a title only — no caption or transcript metadata (owner decision 2026-08-17). Caption enforcement may return as a future feature only if an accessibility audit demands it.
- All payments run through Paymob (electronic wallets + Visa) via the existing checkout/payment flow; this feature adds no new payment path.
- Single-church deployment: tenant scaffolding stays (locked repo pattern, near-zero cost) but no multi-church UI or data ever ships.
- Global videos (free/paid catalog) are already served by the existing `videos`/`video_purchases`/`purchase_video` machinery; this feature adds only the personal-delivery entry point and does not alter catalog behavior.
- Alt text stored per content item in Arabic (single description); multi-language description variants are a future enhancement.
- Unified error contract and its code set are frozen as-is (feature 003); this feature adds messages, not codes.
- Error catalog lives in the database (tenant-scoped editing by admins) — no new external service.
