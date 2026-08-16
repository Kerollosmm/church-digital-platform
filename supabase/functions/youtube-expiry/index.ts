import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { makeServiceClient } from "../_shared/client.ts";
import { respond } from "../_shared/http.ts";

export interface Deps {
  getClient(): unknown;
  fetch: typeof fetch;
  clientId: string;
  clientSecret: string;
  refreshToken: string;
}

export async function handleRequest(
  _req: Request,
  deps: Deps,
): Promise<Response> {
  try {
    const supabase = deps.getClient() as SupabaseClient;
    // videos.update needs OAuth2 (API key is rejected for write ops) — exchange once per run
    const tokRes = await deps.fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "refresh_token",
        client_id: deps.clientId,
        client_secret: deps.clientSecret,
        refresh_token: deps.refreshToken,
      }).toString(),
    });
    if (!tokRes.ok) {
      const errText = await tokRes.text();
      throw new Error(`OAUTH_TOKEN_HTTP_${tokRes.status}: ${errText}`);
    }
    const accessToken = (
      (await tokRes.json()) as { access_token: string }
    ).access_token;

    const { data: videos, error } = await supabase
      .from("videos")
      .select("id, yt_url, event_date, expires_after_days")
      .eq("privacy", "UNLISTED")
      .not("expires_after_days", "is", null);
    if (error) throw error;
    const now = Date.now();
    let flipped = 0;
    for (const v of videos ?? []) {
      const eventTime = new Date(v.event_date as string).getTime();
      const expiryTime =
        eventTime + (v.expires_after_days as number) * 24 * 3600 * 1000;
      if (now < expiryTime) {
        continue; // Video has not expired yet
      }
      const ytMatch = (v.yt_url as string).match(
        /(?:youtu\.be\/|[?&]v=)([a-zA-Z0-9_-]{11})/,
      );
      const videoId = ytMatch
        ? ytMatch[1]
        : ((v.yt_url as string).split("/").pop()?.split("?")[0] ?? "");
      if (!videoId || videoId === "watch") continue;
      const res = await deps.fetch(
        "https://www.googleapis.com/youtube/v3/videos?part=status",
        {
          method: "PUT",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${accessToken}`,
          },
          body: JSON.stringify({
            id: videoId,
            status: { privacyStatus: "PRIVATE" },
          }),
        },
      );
      if (!res.ok) {
        throw new Error(`YOUTUBE_HTTP_${res.status}: ${await res.text()}`);
      }
      await supabase
        .from("videos")
        .update({ privacy: "PRIVATE" })
        .eq("id", v.id);
      flipped++;
    }
    return respond(200, { ok: true, flipped });
  } catch (e: any) {
    console.error("youtube-expiry error", e);
    return respond(500, "INTERNAL", e?.message ?? "YouTube expiry failure");
  }
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
      clientId: Deno.env.get("GOOGLE_CLIENT_ID")!,
      clientSecret: Deno.env.get("GOOGLE_CLIENT_SECRET")!,
      refreshToken: Deno.env.get("GOOGLE_REFRESH_TOKEN")!,
    }),
  );
}
