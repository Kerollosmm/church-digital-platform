# ADR 0004: Free-Content YouTube Media Catalog (Masses/Sermons Automation)

- **Status**: accepted
- **Date**: 2026-08-31

## Context

The original paid-video machinery (`videos`, `video_purchases`, `purchase_video`, `apply_video_payment`, and the `youtube-expiry` cron) was decommissioned by [ADR 0002](./0002-video-to-event-booking-pivot.md) — personal filmed-video sales added operational complexity without matching parish needs. That left the platform with no YouTube automation at all, even though the church broadcasts masses, sermons, and events on a public YouTube channel and parishioners want to browse that content in-app (it aligns with the "Church Services & Masses" and "About Us" pillars in `CONTEXT.md`).

Product intent for 2026-08-31 is to restore YouTube automation as **free, read-only content** — no payments, no access gating, no per-viewer delivery. The catalog is auto-synced from the church's public channel.

## Decision

1. Add a `public.youtube_videos` catalog table (one row per synced YouTube video per tenant) and a public read view `public.v_sermons`, both RLS-gated (`anon` + `authenticated` read of available rows; admin write). No money or booking coupling.
2. Add a single sanctioned write seam: the `SECURITY DEFINER` RPC `sync_youtube_videos(p_channel_id, p_videos)`, revoked from `PUBLIC`/`anon`/`authenticated`, granted to `service_role` only. It upserts a batch on `(tenant_id, yt_video_id)` and marks videos absent from a batch `is_available = false` (removed/made private on YouTube), preserving row identity for stable references.
3. Add the `youtube-sync` Edge Function (YouTube Data API v3): paginates the channel's uploads playlist (`UC… → UU…`), fetches durations in one `videos.list` batch, and calls the RPC. Auth is cron/service-role only (`verifyCronOrServiceAuth`). Zero-leak errors (`UPSTREAM_ERROR`/`INTERNAL`); duration-fetch failures are non-fatal.
4. Schedule a `pg_cron` job (`youtube-sync`, hourly) that posts to the edge function with the service-role key from Vault.

## Consequences

- Real YouTube automation is restored without reintroducing the cancelled payment/video-delivery model.
- All catalog writes flow through one RPC (consistent with the "no raw table business mutations" convention); the edge function only touches the outside world.
- Secrets (`YOUTUBE_API_KEY`, `YOUTUBE_CHANNEL_ID`) live in edge-function secrets/Vault, never in git or the client apps.
- Quota is bounded: ≤150 videos/run (3 pages × 50) + 1 `videos.list` unit per run.
