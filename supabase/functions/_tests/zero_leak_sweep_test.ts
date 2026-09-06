import { assertEquals } from "jsr:@std/assert";
import { handleRequest as analyticsExport } from "../analytics-export/index.ts";
import { handleRequest as diagnosticEngine } from "../diagnostic-engine/index.ts";
import { handleRequest as eventDispatcher } from "../event-dispatcher/index.ts";

// FR-005 sweep: every endpoint's unauthenticated failure body carries exactly
// the frozen code + catalog Arabic sentence — never library/upstream text.
function unauthenticated(): Request {
  return new Request("https://x/functions/v1/sweep", { method: "POST" });
}

async function assertZeroLeak(name: string, res: Response) {
  assertEquals(res.status >= 400, true, `${name} should fail without auth`);
  const body = await res.json();
  assertEquals(
    Object.keys(body).sort(),
    ["error", "message_ar"],
    `${name} body shape violates zero-leak contract`,
  );
  const raw = JSON.stringify(body);
  for (const sentinel of ["Error:", '"stack"', '"message"']) {
    assertEquals(
      raw.includes(sentinel),
      false,
      `${name} leaked ${sentinel}`,
    );
  }
}

Deno.test("sweep: analytics-export", async () => {
  await assertZeroLeak("analytics-export", await analyticsExport(unauthenticated()));
});

Deno.test("sweep: diagnostic-engine", async () => {
  await assertZeroLeak("diagnostic-engine", await diagnosticEngine(unauthenticated()));
});

Deno.test("sweep: event-dispatcher", async () => {
  await assertZeroLeak(
    "event-dispatcher",
    await eventDispatcher(unauthenticated(), {} as never),
  );
});
