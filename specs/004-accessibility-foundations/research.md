# Research: 004-accessibility-foundations

**Date**: 2026-08-17 · **Status**: regenerated post owner-interview (Session 2026-08-17 in spec.md — two video types, captions removed, Paymob-only payments, phone-based delivery) · **Sources**: migrations 0001/0006/0019/0044 recon, feature 003 kernel, conventions.md, WCAG audit 2026-08-16.

## R1: Alt-text storage — central `media_assets`, path-keyed with optional content link

- **Decision**: New table `public.media_assets` keyed by (bucket, storage_path) covering the 3 existing buckets (`priest_photos`, `church_media`, `announcement_images`), with `alt_text_ar`, `is_decorative`, optional (content_type, content_id) link, tenant column with default.
- **Rationale**: Clarify Q1. Schema recon: only `priests.photo_url` is a real image column — `announcements` has **no image column at all**. A path-keyed registry covers all three buckets and any future one, and gives the backlog one source.
- **Alternatives rejected**: per-table columns (announcements would first need an image column; 3 policy sets); storage-object metadata (no RLS, no constraints, not queryable).

## R2: Enforcement — publish/link SECURITY DEFINER RPCs, table CHECK as floor

- **Decision**: Clarify Q2. `publish_announcement(p_id)` refuses to set `published_at` while any linked image lacks alt text/decorative flag; `set_priest_photo(p_priest_id, p_media_asset_id)` validates the asset. `media_assets` carries a CHECK (non-decorative ⇒ non-empty `alt_text_ar`) so the registry cannot hold undescribed rows; announcement write policy gains a matching `WITH CHECK` as defense in depth. church_media imagery has no visibility flip (publish = insert), so the table CHECK + admin-only write policy are its enforcement.
- **Rationale**: Locked convention "state transitions in SECURITY DEFINER RPCs"; RLS + REVOKE-pattern grants block direct-write bypasses. Trigger enforcement rejected (second surface); CHECK-only rejected (cannot distinguish draft saves from publish).

## R3: Personal video delivery — one idempotent RPC, `videos` table untouched

- **Decision**: Owner model (Session 2026-08-17): booking happens with a phone number (official calls to confirm), filming add-on is paid via Paymob, and after the event staff enters phone + YouTube link + title. New RPC `deliver_personal_video(p_phone text, p_yt_url text, p_title_ar text, p_payment_id bigint)`:
  - resolves buyer by **exact** `users.phone` match (NOT NULL UNIQUE, 0001) — no match ⇒ `UNKNOWN_PHONE`, nothing sent;
  - validates `p_payment_id` is PAID and belongs to that user ⇒ else `PAYMENT_INVALID`;
  - **idempotent**: an existing `video_purchases` row for that payment returns the existing video without enqueueing again (double-click/retry safe);
  - creates `videos` row (UNLISTED, price 0, title) + `video_purchases` (access granted) + one `event_outbox` row — template `video_ready`, payload `{video_id, purchase_id, phone}`;
  - the `event-dispatcher` drain sends the WhatsApp message and stamps `link_sent_at`.
  - **No caption/transcript metadata exists** (owner decision — title only). **No `videos` schema change at all** — alters constraints on existing `announcements` (draft state) and `event_outbox` (`video_ready` template).
- **Rationale**: `video_purchases.payment_id` is NOT NULL (0019) — requiring the PAID payment keeps the money boundary intact and gives idempotency a natural key. WhatsApp only via outbox (locked). Global videos (free/paid catalog) already work via `videos.price` + `purchase_video` + Paymob checkout — untouched; links are external YouTube URLs by existing design.
- **Alternatives rejected**: `mark_video_ready` + caption columns (superseded by owner interview); relaxing `payment_id` NOT NULL (touches a money table for no need); direct WhatsApp call from RPC (breaks outbox pattern); "pending deliverables" backlog section (payments carry no filming marker yet — reintroduce only if the add-on gets modeled as its own line item).

## R4: Arabic error catalog — DB table + per-instance TTL cache behind the 003 seam

- **Decision**: Clarify Q3. New `error_messages` (code, message_ar, tenant) seeded with the 5 frozen 003 codes + generic FALLBACK. New `functions/_shared/messages.ts`: loads whole catalog via service client, caches in module memory with 5-minute TTL, exposes `messageFor(code)`. `_shared/http.ts` `respond()` includes `message_ar` on every 4xx/5xx. Lookup failure ⇒ FALLBACK Arabic sentence (FR-007 fail-safe).
- **Alternatives rejected**: fresh lookup per error (slow path on failing requests); static map (violates data-level editability).

## R5: Backlog — images only, view + keyset RPC

- **Decision**: `v_content_backlog` = undescribed images only: (a) `priests.photo_url` values with no matching `media_assets` row, (b) storage objects in the 3 buckets with no `media_assets` row. Staff RPC `get_backlog(p_before_created_at, p_after_id, p_limit<=100)` paginates keyset on (created_at, id text). Video backlog section dropped (R3).
- **Alternatives rejected**: offset paging (skips under concurrent repair); exposing the view directly (needs cursor params + policy anyway).

## Migration numbering

Forward migration **`0049_accessibility_foundations.sql`** (plus forward guard `0051_storage_objects_rls_guard.sql`). Alters constraints on two existing tables (`announcements.published_at DROP NOT NULL` for draft state; `event_outbox_whatsapp_template_check` for `video_ready` template). Two new tables, four new RPCs, one view, seeds, policies on new objects. No new enums (conventions §Enums untouched).
