import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { makeServiceClient } from "./client.ts";

export const FALLBACK_MESSAGE_AR = "حدث خطأ غير متوقع، حاول مرة أخرى.";

export const DEFAULT_CATALOG: Record<string, string> = {
  UNAUTHORIZED: "انتهت الجلسة، من فضلك سجل الدخول مرة أخرى.",
  FORBIDDEN: "ليس لديك صلاحية للوصول إلى هذه الخدمة.",
  BAD_REQUEST: "البيانات المرسلة غير صحيحة، يرجى التأكد والمحاولة مرة أخرى.",
  UPSTREAM_ERROR: "تعذر الاتصال بالخدمة الخارجية، يرجى المحاولة لاحقاً.",
  INTERNAL: "حدث خطأ في النظام، يرجى المحاولة لاحقاً.",
  FALLBACK: "حدث خطأ غير متوقع، حاول مرة أخرى.",
};

export const TTL_MS = 5 * 60 * 1000; // 5 minutes

export interface MessagesCacheOptions {
  client?: SupabaseClient | any;
  getClient?: () => SupabaseClient | any;
  now?: () => number;
}

let cachedCatalog: Map<string, string> | null = null;
let lastFetchedAt = 0;

export function clearMessagesCache(): void {
  cachedCatalog = null;
  lastFetchedAt = 0;
}

export async function refreshCatalog(
  opts?: MessagesCacheOptions,
): Promise<Map<string, string>> {
  const getNow = opts?.now ?? Date.now;
  const client =
    opts?.client ??
    opts?.getClient?.() ??
    (() => {
      try {
        const url =
          typeof Deno !== "undefined" ? Deno.env.get("SUPABASE_URL") : "";
        const key =
          typeof Deno !== "undefined"
            ? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
            : "";
        if (url && key) return makeServiceClient(url, key);
      } catch {
        // fallback
      }
      return null;
    })();

  if (!client) {
    const map = new Map<string, string>(Object.entries(DEFAULT_CATALOG));
    cachedCatalog = map;
    lastFetchedAt = getNow();
    return map;
  }

  try {
    const { data, error } = await client
      .from("error_messages")
      .select("code, message_ar");

    if (error || !data || data.length === 0) {
      const map = new Map<string, string>(Object.entries(DEFAULT_CATALOG));
      cachedCatalog = map;
      lastFetchedAt = getNow();
      return map;
    }

    const map = new Map<string, string>();
    for (const row of data) {
      if (row.code && row.message_ar) {
        map.set(row.code, row.message_ar);
      }
    }
    if (!map.has("FALLBACK")) {
      map.set("FALLBACK", FALLBACK_MESSAGE_AR);
    }
    cachedCatalog = map;
    lastFetchedAt = getNow();
    return map;
  } catch (_err) {
    const map = new Map<string, string>(Object.entries(DEFAULT_CATALOG));
    cachedCatalog = map;
    lastFetchedAt = getNow();
    return map;
  }
}

export async function getCatalog(
  opts?: MessagesCacheOptions,
): Promise<Map<string, string>> {
  const getNow = opts?.now ?? Date.now;
  if (cachedCatalog && getNow() - lastFetchedAt < TTL_MS) {
    return cachedCatalog;
  }
  return await refreshCatalog(opts);
}

export function messageFor(code: string, opts?: MessagesCacheOptions): string {
  const getNow = opts?.now ?? Date.now;
  if (cachedCatalog && getNow() - lastFetchedAt < TTL_MS) {
    return (
      cachedCatalog.get(code) ??
      cachedCatalog.get("FALLBACK") ??
      FALLBACK_MESSAGE_AR
    );
  }
  return (
    DEFAULT_CATALOG[code] ??
    DEFAULT_CATALOG["FALLBACK"] ??
    FALLBACK_MESSAGE_AR
  );
}

export async function messageForAsync(
  code: string,
  opts?: MessagesCacheOptions,
): Promise<string> {
  const catalog = await getCatalog(opts);
  return catalog.get(code) ?? catalog.get("FALLBACK") ?? FALLBACK_MESSAGE_AR;
}
