import { assertEquals } from "jsr:@std/assert";
import { stub } from "jsr:@std/testing/mock";
import { handleRequest, parseIsoDuration, resolveUploadsPlaylist } from "./index.ts";

const SERVICE_KEY = "service_role_secret_123";

function authedReq(): Request {
  return new Request("https://localhost/functions/v1/youtube-sync", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${SERVICE_KEY}`,
    },
    body: "{}",
  });
}

function jsonRes(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// Minimal YouTube Data API fixture.
function playlistItemsPage(items: unknown[], nextPageToken?: string) {
  return { items, nextPageToken, pageInfo: { totalResults: items.length } };
}

const SAMPLE_ITEMS = [
  {
    contentDetails: { videoId: "vid1", videoPublishedAt: "2026-08-20T10:00:00Z" },
    snippet: {
      title: "Mass — Sunday",
      description: "Sunday liturgy",
      publishedAt: "2026-08-20T10:00:00Z",
      thumbnails: { standard: { url: "https://img/v1.jpg" } },
      resourceId: { videoId: "vid1" },
    },
  },
  {
    contentDetails: { videoId: "vid2", videoPublishedAt: "2026-08-13T10:00:00Z" },
    snippet: {
      title: "Sermon — Friday",
      description: "Weekly sermon",
      publishedAt: "2026-08-13T10:00:00Z",
      thumbnails: { high: { url: "https://img/v2.jpg" } },
      resourceId: { videoId: "vid2" },
    },
  },
];

const SAMPLE_DURATIONS = {
  items: [
    { id: "vid1", contentDetails: { duration: "PT1H2M3S" } }, // 3723s
    { id: "vid2", contentDetails: { duration: "PT45M" } }, // 2700s
  ],
};

Deno.test("parseIsoDuration: parses H/M/S and days", () => {
  assertEquals(parseIsoDuration("PT1H2M3S"), 3723);
  assertEquals(parseIsoDuration("PT45M"), 2700);
  assertEquals(parseIsoDuration("PT30S"), 30);
  assertEquals(parseIsoDuration("P1DT2H"), 93600);
  assertEquals(parseIsoDuration(null), null);
  assertEquals(parseIsoDuration("garbage"), null);
});

Deno.test("resolveUploadsPlaylist: UC channel -> UU uploads playlist", () => {
  assertEquals(resolveUploadsPlaylist("UCxxxxxxxxxxxx"), "UUxxxxxxxxxxxx");
  assertEquals(resolveUploadsPlaylist("UUalreadyuploads"), "UUalreadyuploads");
  assertEquals(resolveUploadsPlaylist("PLsomeplaylist"), "PLsomeplaylist");
});

Deno.test("youtube-sync: missing auth returns 401", async () => {
  const req = new Request("https://localhost/functions/v1/youtube-sync", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: "{}",
  });
  const res = await handleRequest(req, {
    getClient: () => ({} as any),
    fetch: () => Promise.resolve(jsonRes({})),
    serviceRoleKey: SERVICE_KEY,
  });
  assertEquals(res.status, 401);
});

Deno.test("youtube-sync: missing API key returns 500 INTERNAL", async () => {
  let captured: string[] = [];
  const fetchStub = stub(
    globalThis,
    "fetch",
    (_url: RequestInfo | URL, _init?: RequestInit) => {
      return Promise.resolve(jsonRes(playlistItemsPage(SAMPLE_ITEMS)));
    },
  );
  try {
    const res = await handleRequest(authedReq(), {
      getClient: () => ({} as any),
      fetch: fetchStub,
      youtubeApiKey: "",
      channelId: "UCchannel",
      serviceRoleKey: SERVICE_KEY,
    });
    assertEquals(res.status, 500);
    const body = await res.json();
    assertEquals(body.error, "INTERNAL");
  } finally {
    fetchStub.restore();
  }
});

Deno.test("youtube-sync: happy path upserts videos and returns counts", async () => {
  const fetchedUrls: string[] = [];
  let rpcCalls = 0;
  let capturedRpc: { p_channel_id: string; p_videos: unknown } | null = null;

  const fetchStub = stub(
    globalThis,
    "fetch",
    (url: RequestInfo | URL, _init?: RequestInit) => {
      const u = String(url);
      fetchedUrls.push(u);
      if (u.includes("/playlistItems")) {
        return Promise.resolve(jsonRes(playlistItemsPage(SAMPLE_ITEMS)));
      }
      if (u.includes("/videos?")) {
        return Promise.resolve(jsonRes(SAMPLE_DURATIONS));
      }
      return Promise.resolve(jsonRes({ items: [] }));
    },
  );

  const fakeClient = {
    rpc: (_name: string, args: Record<string, unknown>) => {
      rpcCalls++;
      capturedRpc = {
        p_channel_id: args.p_channel_id as string,
        p_videos: args.p_videos,
      };
      return Promise.resolve({
        data: { upserted: 2, channel_id: "UCchannel" },
        error: null,
      });
    },
  };

  try {
    const res = await handleRequest(authedReq(), {
      getClient: () => fakeClient as any,
      fetch: fetchStub,
      youtubeApiKey: "yt_key",
      channelId: "UCchannel",
      maxResults: 50,
      serviceRoleKey: SERVICE_KEY,
    });

    assertEquals(res.status, 200);
    const body = await res.json();
    assertEquals(body.ok, true);
    assertEquals(body.synced, 2);
    assertEquals(body.total, 2);
    assertEquals(body.channel_id, "UCchannel");

    // playlistItems hit the derived uploads playlist
    assertEquals(
      fetchedUrls.some((u) => u.includes("playlistId=UUchannel")),
      true,
    );
    // durations batch was fetched
    assertEquals(
      fetchedUrls.some((u) => u.includes("/videos?part=contentDetails")),
      true,
    );
    // RPC called exactly once with the channel id
    assertEquals(rpcCalls, 1);
    assertEquals(capturedRpc!.p_channel_id, "UCchannel");
    const rows = capturedRpc!.p_videos as any[];
    assertEquals(rows.length, 2);
    assertEquals(rows[0].yt_video_id, "vid1");
    assertEquals(rows[0].yt_url, "https://www.youtube.com/watch?v=vid1");
    assertEquals(rows[0].duration_seconds, 3723);
    assertEquals(rows[1].duration_seconds, 2700);
    assertEquals(rows[0].thumbnail_url, "https://img/v1.jpg");
    assertEquals(rows[1].thumbnail_url, "https://img/v2.jpg");
  } finally {
    fetchStub.restore();
  }
});

Deno.test("youtube-sync: YouTube 5xx returns 502 UPSTREAM_ERROR", async () => {
  const fetchStub = stub(
    globalThis,
    "fetch",
    (_url: RequestInfo | URL, _init?: RequestInit) => {
      return Promise.resolve(
        new Response(JSON.stringify({ error: { message: "quota" } }), {
          status: 403,
          headers: { "Content-Type": "application/json" },
        }),
      );
    },
  );
  try {
    const res = await handleRequest(authedReq(), {
      getClient: () => ({} as any),
      fetch: fetchStub,
      youtubeApiKey: "yt_key",
      channelId: "UCchannel",
      serviceRoleKey: SERVICE_KEY,
    });
    assertEquals(res.status, 502);
    const body = await res.json();
    assertEquals(body.error, "UPSTREAM_ERROR");
  } finally {
    fetchStub.restore();
  }
});

Deno.test("youtube-sync: RPC error returns 500 INTERNAL", async () => {
  const fetchStub = stub(
    globalThis,
    "fetch",
    (_url: RequestInfo | URL, _init?: RequestInit) => {
      return Promise.resolve(jsonRes(playlistItemsPage(SAMPLE_ITEMS)));
    },
  );
  const fakeClient = {
    rpc: () => Promise.resolve({ data: null, error: { message: "boom" } }),
  };
  try {
    const res = await handleRequest(authedReq(), {
      getClient: () => fakeClient as any,
      fetch: fetchStub,
      youtubeApiKey: "yt_key",
      channelId: "UCchannel",
      serviceRoleKey: SERVICE_KEY,
    });
    assertEquals(res.status, 500);
    const body = await res.json();
    assertEquals(body.error, "INTERNAL");
  } finally {
    fetchStub.restore();
  }
});

Deno.test("youtube-sync: empty catalog returns synced 0 without RPC error", async () => {
  const fetchStub = stub(
    globalThis,
    "fetch",
    (_url: RequestInfo | URL, _init?: RequestInit) => {
      return Promise.resolve(jsonRes(playlistItemsPage([])));
    },
  );
  let rpcCalled = false;
  const fakeClient = {
    rpc: () => {
      rpcCalled = true;
      return Promise.resolve({ data: { upserted: 0 }, error: null });
    },
  };
  try {
    const res = await handleRequest(authedReq(), {
      getClient: () => fakeClient as any,
      fetch: fetchStub,
      youtubeApiKey: "yt_key",
      channelId: "UCchannel",
      serviceRoleKey: SERVICE_KEY,
    });
    assertEquals(res.status, 200);
    const body = await res.json();
    assertEquals(body.synced, 0);
    assertEquals(body.total, 0);
    // RPC not invoked when no videos were fetched
    assertEquals(rpcCalled, false);
  } finally {
    fetchStub.restore();
  }
});
