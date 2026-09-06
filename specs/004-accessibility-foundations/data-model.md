# Data Model: 004-accessibility-foundations

All changes in forward migration `0049_accessibility_foundations.sql` (with `0051_storage_objects_rls_guard.sql` forward counterpart). Alters constraints on two existing tables (`announcements.published_at DROP NOT NULL` to permit draft state; `event_outbox_whatsapp_template_check` drop/re-add to permit `video_ready` template) — no column additions anywhere, no new enums. Test suite `tests/0049_accessibility_test.sql` registered in `run_all.sql` (negative-auth asserts mandatory per FR-011).

## New: `public.media_assets`

| Column | Type | Rules |
|--------|------|-------|
| id | bigint generated always as identity PK | `USAGE, SELECT` on sequence granted to authenticated |
| bucket | text NOT NULL | CHECK in ('priest_photos','church_media','announcement_images') |
| storage_path | text NOT NULL | object path inside bucket |
| alt_text_ar | text | CHECK: NULL allowed only when is_decorative; else trim length > 0 |
| is_decorative | boolean NOT NULL DEFAULT false | decorative ⇒ screen readers skip |
| content_type | text NULL | CHECK in ('announcement','priest','media') when present |
| content_id | bigint NULL | owning content row when content_type present |
| language | text NOT NULL DEFAULT 'ar' | FR-003 Arabic-first |
| tenant_id | bigint NOT NULL DEFAULT public.tenant_id() | tenant invariant |

- UNIQUE (bucket, storage_path, tenant_id).
- RLS enabled; SELECT `TO anon, authenticated` + tenant check (alt text is public content); ALL write `TO authenticated` + `public.is_admin()` + tenant check.
- Arabic preserved verbatim (FR-003).

## New: `public.error_messages`

| Column | Type | Rules |
|--------|------|-------|
| code | text PK | CHECK in ('UNAUTHORIZED','FORBIDDEN','BAD_REQUEST','UPSTREAM_ERROR','INTERNAL','FALLBACK') — 003 codes frozen |
| message_ar | text NOT NULL | one short sentence (TTS guidance) |
| tenant_id | bigint NOT NULL DEFAULT public.tenant_id() | tenant invariant |

- Seed 6 rows (5 codes + FALLBACK) with Arabic sentences.
- RLS enabled; SELECT to anon, authenticated + tenant; write admin-only (`is_admin()`).

## Existing tables — modifications & reuse

- `announcements`: `ALTER COLUMN published_at DROP NOT NULL` (enables saving draft announcements before publishing).
- `event_outbox`: `event_outbox_whatsapp_template_check` dropped and re-added to include `'video_ready'` template in allowed list.
- `videos`, `video_purchases`, `priests`, `payments`: **zero schema changes.** Personal delivery reuses `videos` (title_ar, yt_url, privacy='UNLISTED', price=0) and `video_purchases` (payment_id, user_id, access_granted_at, link_sent_at) exactly as they are.

## New RPCs (all SECURITY DEFINER, `SET search_path = public, pg_temp`, REVOKE ALL FROM PUBLIC/anon/authenticated → targeted grant + negative-auth tests)

### `publish_announcement(p_id bigint) RETURNS void`
Grant: `authenticated`; internal `is_admin_or_priest()` check.
- Image detection rule: because `announcements` has no image column, the RPC infers imagery if `body_ar LIKE '%announcement_images%'` OR `storage.objects` contains objects in `announcement_images` bucket prefixed `ann{id}/` or `{id}/`.
- Raises `ALT_TEXT_REQUIRED` if images are detected but linked `media_assets` (content_type='announcement', content_id=p_id) have zero rows, or any linked non-decorative asset is missing `alt_text_ar`.
- Sets `published_at = now()`, `updated_at = now()`.

### `set_priest_photo(p_priest_id bigint, p_media_asset_id bigint) RETURNS void`
Grant: `authenticated`; internal `is_admin()` check.
- Validates asset (bucket='priest_photos', alt valid); links it and updates `priests.photo_url`.

### `deliver_personal_video(p_phone text, p_yt_url text, p_title_ar text, p_payment_id bigint) RETURNS bigint`
Grant: `service_role` (staff console / edge seam).
- `UNKNOWN_PHONE`: no user with exactly this `users.phone` → refuse, nothing sent.
- `PAYMENT_INVALID`: payment missing / not PAID / not that user's → refuse.
- Idempotent: existing `video_purchases` for `p_payment_id` → return its video id, **no** new rows, **no** new event.
- Success (single transaction): create `videos` row (title, yt_url, UNLISTED, price 0, tenant default), create `video_purchases` (user, payment, `access_granted_at = now()`), insert one `event_outbox` row — template `video_ready`, payload `{video_id, purchase_id, phone}`. Returns video id.
- Never appears in public catalog (no catalog list policy change needed — personal videos are read via `video_purchases` own-read policy, which already exists).

### `get_backlog(p_before_created_at timestamptz, p_after_id text, p_limit int) RETURNS jsonb`
Grant: `service_role` (staff console / edge seam).
- Keyset pagination on `(source_created_at DESC, id DESC)` over `v_content_backlog`; `p_limit` capped 100; returns `{ items, next_cursor }` where `next_cursor` carries `{created_at, id}` with `id` as string.

## New view: `v_content_backlog`
Images only (video backlog dropped — research R3): (a) `priests.photo_url` with no `media_assets` row, (b) storage objects in the 3 buckets with no `media_assets` row. One row per offender: `kind='missing_alt_text'`, `source_created_at`, `id text` (`'priest:' || id` or `'object:' || id`), `label`. Access revoked from anon/authenticated; consumed only by `get_backlog`.

## Edge-function side

- `_shared/messages.ts` (new): catalog cache, 5-min TTL, `messageFor(code)`; failure ⇒ FALLBACK.
- `_shared/http.ts` (extend): `respond()` adds `message_ar` to every 4xx/5xx body. Codes unchanged.
- `event-dispatcher` (extend): `video_ready` template handler — send WhatsApp message with the YouTube link, stamp `video_purchases.link_sent_at` on success.

## State transitions

- Personal video: `paid add-on` (PAID payment) → `delivered` (`deliver_personal_video` succeeds: video + access + outbox event) → `sent` (drain stamps `link_sent_at`). No intermediate ready state, no caption gate.
- Announcement: draft (`published_at` NULL) → published (RPC only). Alt-text gate sits at the flip.
