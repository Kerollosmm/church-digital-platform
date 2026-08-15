import { assertEquals } from "jsr:@std/assert";
import { stub } from "jsr:@std/testing/mock";
import { handleRequest } from "./index.ts";
import { FakeClient } from "../_shared/fake_supabase.ts";

function jsonRes(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

Deno.test("youtube-expiry: exchanges refresh token, flips UNLISTED->PRIVATE after expires_after_days and marks privacy", async () => {
  const fake = new FakeClient(["videos"]);
  const past = new Date(Date.now() - 40 * 24 * 3600 * 1000).toISOString();
  fake.seed("videos", [{ id: 1, yt_url: "https://youtu.be/abc123", privacy: "UNLISTED", event_date: past, expires_after_days: 30 }]);
  const calls: { url: string; body: string; auth?: string | null }[] = [];
  const fetchStub = stub(globalThis, "fetch", (url: RequestInfo | URL, init?: RequestInit) => {
    const h = init?.headers as Record<string, string> | undefined;
    calls.push({ url: String(url), body: String(init?.body), auth: h?.["Authorization"] });
    if (String(url).includes("oauth2.googleapis.com/token")) return Promise.resolve(jsonRes({ access_token: "at1", expires_in: 3600 }));
    return Promise.resolve(jsonRes({ etag: "x" }));
  });
  try {
    const res = await handleRequest(new Request("https://x/functions/v1/youtube-expiry", { method: "POST" }), {
      getClient: () => fake as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
      fetch: fetchStub, clientId: "cid", clientSecret: "csec", refreshToken: "rtok",
    });
    assertEquals(res.status, 200);
    // 1) token exchange, 2) videos.update
    assertEquals(calls.length, 2);
    assertEquals(calls[0].url, "https://oauth2.googleapis.com/token");
    const body = new URLSearchParams(calls[0].body);
    assertEquals(body.get("grant_type"), "refresh_token");
    assertEquals(body.get("refresh_token"), "rtok");
    assertEquals(calls[1].url, "https://www.googleapis.com/youtube/v3/videos?part=status");
    assertEquals(calls[1].auth, "Bearer at1");
    const vid = JSON.parse(calls[1].body);
    assertEquals(vid.id, "abc123");
    assertEquals(vid.status.privacyStatus, "PRIVATE");
    assertEquals(fake.tableRows("videos")[0].privacy, "PRIVATE");
  } finally { fetchStub.restore(); }
});
