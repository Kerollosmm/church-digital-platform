import { assertEquals } from "jsr:@std/assert";
import {
  messageFor,
  getCatalog,
  refreshCatalog,
  clearMessagesCache,
  FALLBACK_MESSAGE_AR,
  DEFAULT_CATALOG,
  TTL_MS,
} from "../_shared/messages.ts";
import { FakeClient } from "../_shared/fake_supabase.ts";

Deno.test("messages: messageFor() returns catalog Arabic for all 5 frozen error codes", () => {
  clearMessagesCache();
  assertEquals(messageFor("UNAUTHORIZED"), "انتهت الجلسة، من فضلك سجل الدخول مرة أخرى.");
  assertEquals(messageFor("FORBIDDEN"), "ليس لديك صلاحية للوصول إلى هذه الخدمة.");
  assertEquals(messageFor("BAD_REQUEST"), "البيانات المرسلة غير صحيحة، يرجى التأكد والمحاولة مرة أخرى.");
  assertEquals(messageFor("UPSTREAM_ERROR"), "تعذر الاتصال بالخدمة الخارجية، يرجى المحاولة لاحقاً.");
  assertEquals(messageFor("INTERNAL"), "حدث خطأ في النظام، يرجى المحاولة لاحقاً.");
});

Deno.test("messages: messageFor() returns FALLBACK for unknown error codes", () => {
  clearMessagesCache();
  assertEquals(messageFor("UNKNOWN_CODE"), FALLBACK_MESSAGE_AR);
  assertEquals(messageFor("SOME_RANDOM_ERROR"), FALLBACK_MESSAGE_AR);
});

Deno.test("messages: cache hit within TTL (1 fetch across many calls with fake clock)", async () => {
  clearMessagesCache();
  let fetchCount = 0;
  const fake = new FakeClient(["error_messages"]);
  fake.seed("error_messages", [
    { code: "UNAUTHORIZED", message_ar: "نص مخصص 1" },
    { code: "BAD_REQUEST", message_ar: "نص مخصص 2" },
  ]);

  // Wrap query to count fetches
  const originalFrom = fake.from.bind(fake);
  fake.from = (table: string) => {
    if (table === "error_messages") {
      fetchCount++;
    }
    return originalFrom(table);
  };

  let simulatedTime = 1_000_000;
  const clock = () => simulatedTime;

  // First call fetches from DB
  const cat1 = await getCatalog({ client: fake as any, now: clock });
  assertEquals(fetchCount, 1);
  assertEquals(cat1.get("UNAUTHORIZED"), "نص مخصص 1");
  assertEquals(messageFor("UNAUTHORIZED", { now: clock }), "نص مخصص 1");

  // Subsequent calls within TTL (simulatedTime + 2 minutes < 5 minutes)
  simulatedTime += 2 * 60 * 1000;
  const cat2 = await getCatalog({ client: fake as any, now: clock });
  assertEquals(fetchCount, 1); // No new fetch
  assertEquals(cat2.get("UNAUTHORIZED"), "نص مخصص 1");
  assertEquals(messageFor("UNAUTHORIZED", { now: clock }), "نص مخصص 1");

  // Call right before TTL expiry (4 min 59 sec)
  simulatedTime += 2 * 60 * 1000 + 59 * 1000;
  await getCatalog({ client: fake as any, now: clock });
  assertEquals(fetchCount, 1);
});

Deno.test("messages: reload after TTL expiry", async () => {
  clearMessagesCache();
  let fetchCount = 0;
  const fake = new FakeClient(["error_messages"]);
  fake.seed("error_messages", [
    { code: "UNAUTHORIZED", message_ar: "النسخة القديمة" },
  ]);

  const originalFrom = fake.from.bind(fake);
  fake.from = (table: string) => {
    if (table === "error_messages") {
      fetchCount++;
    }
    return originalFrom(table);
  };

  let simulatedTime = 2_000_000;
  const clock = () => simulatedTime;

  await getCatalog({ client: fake as any, now: clock });
  assertEquals(fetchCount, 1);
  assertEquals(messageFor("UNAUTHORIZED", { now: clock }), "النسخة القديمة");

  // Update DB row
  fake.seed("error_messages", [
    { code: "UNAUTHORIZED", message_ar: "النسخة المحدثة" },
  ]);

  // Advance time past TTL (simulatedTime + 5 minutes + 1 second)
  simulatedTime += TTL_MS + 1000;

  const cat = await getCatalog({ client: fake as any, now: clock });
  assertEquals(fetchCount, 2); // Re-fetched
  assertEquals(cat.get("UNAUTHORIZED"), "النسخة المحدثة");
  assertEquals(messageFor("UNAUTHORIZED", { now: clock }), "النسخة المحدثة");
});

Deno.test("messages: lookup failure on empty/error DB returns FALLBACK message", async () => {
  clearMessagesCache();
  const fake = new FakeClient(["error_messages"]);
  // DB query error / empty
  fake.seed("error_messages", []);

  const cat = await refreshCatalog({ client: fake as any });
  assertEquals(cat.get("FALLBACK"), FALLBACK_MESSAGE_AR);
  assertEquals(messageFor("NON_EXISTENT_CODE"), FALLBACK_MESSAGE_AR);
});
