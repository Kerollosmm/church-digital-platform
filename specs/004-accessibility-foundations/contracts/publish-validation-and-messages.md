# Contract: Publish Validation, Video Delivery, Backlog, Localized Errors

Audience: admin console (staff), mobile client, edge functions, tests. Error codes are frozen (feature 003); this feature adds messages and gates, not codes.

## 1. Media asset registration (staff)

```
media_assets(bucket, storage_path, alt_text_ar, is_decorative, content_type?, content_id?)
```

- Non-decorative rows REQUIRE non-empty `alt_text_ar` (CHECK) — Arabic stored verbatim.
- Decorative rows: `alt_text_ar` NULL, `is_decorative = true` ⇒ clients hide from screen readers.
- Read: any client (anon/authenticated) within tenant; write: admins only.
- Linkage: announcement imagery passes `content_type='announcement', content_id=<id>`; priest photos via `set_priest_photo`; church media unlinked (published on insert).

## 2. Publish gates (RPC contract)

| RPC | Caller | Refusal (exception) | Success |
|-----|--------|--------------------|---------|
| `publish_announcement(p_id)` | staff (is_admin_or_priest) | `ALT_TEXT_REQUIRED` — linked images missing alt/decorative, or images present with zero linked assets | `published_at = now()` |
| `set_priest_photo(p_priest_id, p_media_asset_id)` | admin | `INVALID_MEDIA_ASSET` — wrong bucket / missing / invalid alt | asset linked, `photo_url` updated |

Note on image detection: `announcements` has no dedicated image column; `publish_announcement` infers imagery from `body_ar` containing `announcement_images` or `storage.objects` prefixed `ann{id}/` or `{id}/`.

Refusals have no partial effects (single transaction).

## 3. Personal video delivery (staff → buyer's WhatsApp)

### Database RPC Seam

```sql
deliver_personal_video(p_phone text, p_yt_url text, p_title_ar text, p_payment_id bigint) → video_id bigint
```

- Refusals: `UNKNOWN_PHONE` (no exact `users.phone` match — nothing sent), `PAYMENT_INVALID` (payment not PAID / not this user's).
- Idempotent: same payment delivered again → returns existing video_id, no duplicate rows, no duplicate WhatsApp message.
- Success: unlisted video created (title + YouTube URL only — **no caption/transcript fields exist**), buyer access granted, one outbox event queued.
- Outbox payload: `{ template_name: 'video_ready', video_id, purchase_id, phone }`; drain sends WhatsApp and stamps `link_sent_at`.
- Buyer reads it through `video_purchases` (own-read policy, existing). Personal videos never appear in the public catalog.

### HTTP Surface (Edge Function Seam)

- **Method**: `POST`
- **Path**: `/functions/v1/deliver-personal-video`
- **Headers**:
  - `Authorization: Bearer <staff_jwt>` (Requires `ADMIN` or `SUPER_ADMIN` role in `public.users`)
  - `Content-Type: application/json`
- **Request Body**:
  ```json
  {
    "phone": "+201012345678",
    "yt_url": "https://youtu.be/baptism101",
    "title_ar": "فيديو سر المعمودية المقدس — طفل جورج",
    "payment_id": 501
  }
  ```
- **Success Body (200 OK)**:
  ```json
  {
    "video_id": 101
  }
  ```
- **Error Mapping Table**:

| HTTP Status | Code (`error`) | Reason (`reason`) | Cause / Condition | `message_ar` Source |
|---|---|---|---|---|
| 401 | `UNAUTHORIZED` | — | Missing, invalid, or expired Bearer token | `error_messages` catalog |
| 403 | `FORBIDDEN` | — | Caller role is not `ADMIN`/`SUPER_ADMIN`, or role lookup failed | `error_messages` catalog |
| 400 | `BAD_REQUEST` | — | Non-POST method, malformed JSON, empty string (`phone`/`title_ar`), invalid `yt_url` host/protocol, or non-positive integer `payment_id` | `error_messages` catalog |
| 400 | `BAD_REQUEST` | `UNKNOWN_PHONE` | RPC raised `UNKNOWN_PHONE` (no exact phone match in `public.users`) | `error_messages` catalog |
| 400 | `BAD_REQUEST` | `PAYMENT_INVALID` | RPC raised `PAYMENT_INVALID` (payment missing, not `PAID`, or not matching user's booking) | `error_messages` catalog |
| 500 | `INTERNAL` | — | Unexpected database or runtime error (zero exception text leaked) | `error_messages` catalog |

## 4. Global videos (existing behavior, restated for clarity)

- Public catalog entries with external YouTube links (navigate to YouTube, never embedded in-app).
- Free or paid per video: `price = 0` free; paid → existing Paymob checkout (wallets + Visa) → `purchase_video` / `apply_video_payment` flow — unchanged by this feature.

## 5. Backlog (staff, keyset)

```
get_backlog(p_before_created_at timestamptz, p_after_id text, p_limit<=100) →
  { items: [{kind: 'missing_alt_text', id: text, created_at, label, ...}],
    next_cursor: {created_at: string, id: string} | null }
```

- Caller: `service_role` only.
- Images only: orphan priest photos + unlinked bucket objects.
- Keyset on `(source_created_at DESC, id DESC)`: client passes previous page's cursor `{created_at, id}` (where `id` is a string such as `'priest:123'` or `'object:uuid'`); first page passes NULLs. Stable under concurrent repair.

## 6. Localized error messages (clients)

Response body on every 4xx/5xx (003 shape extended):

```json
{ "error": "UNAUTHORIZED", "message_ar": "انتهت الجلسة، من فضلك سجل الدخول مرة أخرى." }
```

- `error`: frozen machine code (unchanged set).
- `message_ar`: non-empty Arabic sentence from `error_messages` via `_shared/messages.ts` 5-min cache; unknown/failed lookup ⇒ FALLBACK sentence ("حدث خطأ غير متوقع، حاول مرة أخرى.").
- Rewording = data-level update; propagates within TTL without deployment (FR-007).
- Screen readers announce `message_ar`; clients MUST NOT display `error` raw to end users.
