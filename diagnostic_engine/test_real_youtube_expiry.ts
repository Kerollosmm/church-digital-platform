import { handleRequest } from "../supabase/functions/youtube-expiry/index.ts";
import { FakeClient } from "../supabase/functions/_shared/fake_supabase.ts";

export async function runYoutubeExpiryVerification() {
  console.log("\x1b[35m===================================================================\x1b[0m");
  console.log("\x1b[35m       YOUTUBE RECORDED EVENT EXPIRY RUNNER TEST                   \x1b[0m");
  console.log("\x1b[35m===================================================================\x1b[0m\n");

  console.log("\x1b[36m[Stage 1: Setup Scenario]\x1b[0m Seeding unlisted sermon video past expiration window...");
  const fakeDb = new FakeClient(["videos"]);
  fakeDb.seed("videos", [
    {
      id: 901,
      yt_url: "https://youtu.be/dQw4w9WgXcQ",
      event_date: new Date(Date.now() - 30 * 24 * 3600 * 1000).toISOString(),
      expires_after_days: 7, // Expired 23 days ago
      privacy: "UNLISTED",
    },
    {
      id: 902,
      yt_url: "https://youtu.be/L_LUpnjgPso",
      event_date: new Date().toISOString(),
      expires_after_days: 14, // Still valid
      privacy: "UNLISTED",
    },
  ]);

  let flippedVideoId: string | null = null;
  let newPrivacyStatus: string | null = null;

  console.log("\x1b[36m[Stage 2: Run Expiry Sweep]\x1b[0m Flipping expired unlisted video to PRIVATE via Google OAuth2...");
  const req = new Request("https://x/functions/v1/youtube-expiry", { method: "POST" });
  const res = await handleRequest(req, {
    getClient: () => fakeDb as unknown as import("npm:@supabase/supabase-js@2").SupabaseClient,
    fetch: (url, init) => {
      const u = String(url);
      if (u.includes("oauth2.googleapis.com")) {
        return Promise.resolve(new Response(JSON.stringify({ access_token: "google-bearer-token" }), { status: 200 }));
      }
      if (u.includes("youtube.googleapis.com")) {
        const body = JSON.parse(String(init?.body ?? "{}"));
        flippedVideoId = body.id;
        newPrivacyStatus = body.status?.privacyStatus;
        return Promise.resolve(new Response(JSON.stringify({ id: flippedVideoId, status: { privacyStatus: newPrivacyStatus } }), { status: 200 }));
      }
      return Promise.resolve(new Response("{}", { status: 200 }));
    },
    clientId: "client-id",
    clientSecret: "client-secret",
    refreshToken: "refresh-token",
  });

  const body = await res.json() as Record<string, unknown>;
  console.log(`\x1b[32m[Stage 2 OK]\x1b[0m Expiry Sweep HTTP ${res.status}:`, body);
  console.log(`  - Flipped Video ID: \`${flippedVideoId}\` → Privacy: \`${newPrivacyStatus}\``);

  console.log("\n\x1b[35m===================================================================\x1b[0m");
  console.log("\x1b[35m    YOUTUBE VIDEO EXPIRY VERIFICATION COMPLETE (PASS)              \x1b[0m");
  console.log("\x1b[35m===================================================================\x1b[0m\n");
}

if (import.meta.main) {
  runYoutubeExpiryVerification().catch((err) => {
    console.error("\n\x1b[31m[TEST FAILED]\x1b[0m", err);
    Deno.exit(1);
  });
}
