// youtube-sync: refreshes the free-content YouTube catalog (masses/sermons)
// from the church's public channel via the YouTube Data API v3 and upserts the
// results through the `sync_youtube_videos` SECURITY DEFINER RPC.
//
// Auth: pg_cron / service-role (verifyCronOrServiceAuth). No client auth — this
// is a background job. All DB writes go through the RPC; the function only
// touches the outside world (YouTube).
//
// Secrets: YOUTUBE_API_KEY, YOUTUBE_CHANNEL_ID (UCxxxxxx). Optional page cap
// via YOUTUBE_MAX_RESULTS (default 50, capped at 50 by the API per page).

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { makeServiceClient } from "../_shared/client.ts";
import { respond, verifyCronOrServiceAuth } from "../_shared/http.ts";

export const MAX_RESULTS = 50;

export interface Deps {
  getClient(): SupabaseClient;
  fetch: typeof fetch;
  youtubeApiKey?: string;
  channelId?: string;
  maxResults?: number;
  cronSecret?: string;
  serviceRoleKey?: string;
}

interface VideoRow {
  yt_video_id: string;
  title: string;
  description: string;
  thumbnail_url: string;
  yt_url: string;
  published_at: string | null;
  duration_seconds: number | null;
}

// Parse ISO-8601 duration (PT#H#M#S, optionally with days) to seconds.
export function parseIsoDuration(iso: string | null | undefined): number | null {
  if (!iso) return null;
  const m = iso.match(
    /^P(?:(\d+)D)?T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?$/,
  );
  if (!m) return null;
  const days = Number(m[1] ?? 0);
  const hours = Number(m[2] ?? 0);
  const mins = Number(m[3] ?? 0);
  const secs = Number(m[4] ?? 0);
  const total = days * 86400 + hours * 3600 + mins * 60 + secs;
  return Number.isInteger(total) ? total : Math.floor(total);
}

// The uploads playlist of a channel UCxxxx is UUxxxx. Accept either a channel
// id, a pre-built uploads playlist id, or any playlist id directly.
export function resolveUploadsPlaylist(channelId: string): string {
  if (/^UU|^(PL|FL|OL|RD)/.test(channelId)) return channelId;
  if (channelId.startsWith("UC")) return "UU" + channelId.slice(2);
  return channelId;
}

async function fetchJson(
  deps: Deps,
  url: string,
): Promise<{ ok: boolean; status: number; body: any }> {
  try {
    const res = await deps.fetch(url, { method: "GET" });
    const text = await res.text();
    let body: any = null;
    try {
      body = text ? JSON.parse(text) : null;
    } catch {
      body = text;
    }
    return { ok: res.ok, status: res.status, body };
  } catch (err) {
    console.error("youtube-sync fetch error:", err);
    return { ok: false, status: 0, body: null };
  }
}

function pickThumbnail(snippet: any): string {
  const t = snippet?.thumbnails;
  if (!t) return "";
  return (
    t.standard?.url ?? t.high?.url ?? t.medium?.url ?? t.maxres?.url ??
      t.default?.url ?? ""
  );
}

export async function handleRequest(
  req: Request,
  deps: Deps,
): Promise<Response> {
  const authErr = verifyCronOrServiceAuth(req, {
    cronSecret: deps.cronSecret,
    serviceRoleKey: deps.serviceRoleKey,
  });
  if (authErr) return authErr;

  const apiKey =
    deps.youtubeApiKey ??
    (typeof Deno !== "undefined" ? Deno.env.get("YOUTUBE_API_KEY") : "") ?? "";
  const channelId =
    deps.channelId ??
    (typeof Deno !== "undefined" ? Deno.env.get("YOUTUBE_CHANNEL_ID") : "") ??
    "";

  if (!apiKey) {
    console.error("youtube-sync: YOUTUBE_API_KEY not configured");
    return respond(500, "INTERNAL", "Missing YouTube API key");
  }
  if (!channelId) {
    console.error("youtube-sync: YOUTUBE_CHANNEL_ID not configured");
    return respond(500, "INTERNAL", "Missing YouTube channel id");
  }

  const limit = Math.min(
    deps.maxResults ??
      (typeof Deno !== "undefined"
        ? Number(Deno.env.get("YOUTUBE_MAX_RESULTS") ?? MAX_RESULTS)
        : MAX_RESULTS),
    MAX_RESULTS,
  );

  const playlistId = resolveUploadsPlaylist(channelId);
  const videos: VideoRow[] = [];
  const idToRow = new Map<string, VideoRow>();
  let pageToken: string | undefined = undefined;
  let pages = 0;
  const maxPages = 3; // hard cap to bound quota (<=150 videos/run)

  // 1. Paginate playlistItems (uploads) up to the limit.
  while (pages < maxPages) {
    let pageUrl =
      `https://www.googleapis.com/youtube/v3/playlistItems?part=snippet,contentDetails` +
      `&playlistId=${encodeURIComponent(playlistId)}&maxResults=${limit}&key=${apiKey}`;
    if (pageToken) pageUrl += `&pageToken=${encodeURIComponent(pageToken)}`;

    const page = await fetchJson(deps, pageUrl);
    if (!page.ok) {
      console.error(
        `youtube-sync: playlistItems HTTP ${page.status}`,
        page.body?.error?.message ?? "",
      );
      return respond(502, "UPSTREAM_ERROR");
    }

    const items = Array.isArray(page.body?.items) ? page.body.items : [];
    for (const it of items) {
      const videoId = it?.contentDetails?.videoId ?? it?.snippet?.resourceId
        ?.videoId;
      if (!videoId) continue;
      const snippet = it?.snippet ?? {};
      const row: VideoRow = {
        yt_video_id: String(videoId),
        title: String(snippet.title ?? ""),
        description: String(snippet.description ?? ""),
        thumbnail_url: pickThumbnail(snippet),
        yt_url: `https://www.youtube.com/watch?v=${videoId}`,
        published_at: snippet.publishedAt ?? it?.contentDetails
            ?.videoPublishedAt ?? null,
        duration_seconds: null,
      };
      videos.push(row);
      idToRow.set(row.yt_video_id, row);
    }

    if (videos.length >= limit) break;
    pageToken = page.body?.nextPageToken;
    if (!pageToken) break;
    pages++;
  }

  // 2. Fetch durations in a single videos.list batch (1 quota unit / 50 ids).
  if (idToRow.size > 0) {
    const ids = Array.from(idToRow.keys()).slice(0, 50).join(",");
    const durUrl =
      `https://www.googleapis.com/youtube/v3/videos?part=contentDetails` +
      `&id=${encodeURIComponent(ids)}&key=${apiKey}`;
    const durRes = await fetchJson(deps, durUrl);
    if (durRes.ok && Array.isArray(durRes.body?.items)) {
      for (const v of durRes.body.items) {
        const vid = v?.id;
        const secs = parseIsoDuration(v?.contentDetails?.duration);
        const row = vid ? idToRow.get(String(vid)) : undefined;
        if (row) row.duration_seconds = secs;
      }
    }
    // Duration fetch failure is non-fatal: catalog still upserts without it.
  }

  if (videos.length === 0) {
    return respond(200, { ok: true, synced: 0, total: 0, channel_id: channelId });
  }

  // 3. Upsert through the sanctioned RPC (no direct table writes).
  const client = deps.getClient();
  const { data, error } = await client.rpc("sync_youtube_videos", {
    p_channel_id: channelId,
    p_videos: videos,
  });

  if (error) {
    console.error("youtube-sync: sync_youtube_videos RPC failed:", error);
    return respond(500, "INTERNAL", "Catalog sync failed");
  }

  const result = (data ?? {}) as { upserted?: number; channel_id?: string };
  return respond(200, {
    ok: true,
    synced: result.upserted ?? videos.length,
    total: videos.length,
    channel_id: channelId,
  });
}

if (import.meta.main && typeof Deno !== "undefined" && Deno.serve) {
  Deno.serve((req) =>
    handleRequest(req, {
      getClient: () =>
        makeServiceClient(
          Deno.env.get("SUPABASE_URL"),
          Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
        ),
      fetch,
      cronSecret: Deno.env.get("CRON_SECRET"),
      serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
    }),
  );
}
