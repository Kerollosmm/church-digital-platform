import { assertEquals, assertExists } from "jsr:@std/assert";
import {
  BrainAgent,
  AuditorAgent,
  SystemCatalog,
  TestVector,
  ExecutionResult,
} from "./engine.ts";

const mockCatalog: SystemCatalog = {
  tables: {
    users: { name: "users", columns: [], rlsEnabled: true },
    audit_log: { name: "audit_log", columns: [], rlsEnabled: true },
    bookings: { name: "bookings", columns: [], rlsEnabled: true },
    services: { name: "services", columns: [], rlsEnabled: true },
    service_slots: { name: "service_slots", columns: [], rlsEnabled: true },
  },
  rpcs: {
    book_slot: { name: "book_slot", args: [], isSecurityDefiner: true },
    fn_book_slot_atomic: { name: "fn_book_slot_atomic", args: [], isSecurityDefiner: true },
  },
  enums: {
    app_role: ["PARISHIONER", "SERVANT", "ADMIN", "SUPER_ADMIN"],
  },
  edgeFunctions: [
    { slug: "paymob-webhook", path: "/functions/v1/paymob-webhook", method: "POST", requiresAuth: false },
  ],
};

const mockContext = {
  slotId: 42,
  bookingId: 100,
  parishionerUid: "parishioner-uuid-0001",
};

Deno.test("BrainAgent.synthesizeVectors generates complete security and functional vectors", () => {
  const brain = new BrainAgent();
  const vectors = brain.synthesizeVectors(mockCatalog, mockContext);

  assertExists(vectors);
  assertEquals(vectors.length > 0, true);

  const requiredIds = [
    "SEC-ANON-USERS-READ",
    "SEC-ANON-AUDIT-LOG-READ",
    "SEC-ANON-DIRECT-BOOKING-INSERT",
    "SEC-ANON-BOOK-SLOT-RPC",
  ];

  for (const id of requiredIds) {
    const vector = vectors.find((v) => v.id === id);
    assertExists(vector, `Expected test vector ${id} to be generated`);
    assertEquals(
      vector.expectedOutcome,
      "PERMISSION_DENIED",
      `Expected ${id} to require PERMISSION_DENIED outcome`,
    );
  }
});

Deno.test("AuditorAgent.audit identifies critical RLS violation when forbidden operation succeeds", () => {
  const auditor = new AuditorAgent();
  const vector: TestVector = {
    id: "SEC-ANON-DIRECT-BOOKING-INSERT",
    title: "Anonymous direct INSERT on 'bookings' table (Must block via RLS)",
    category: "SECURITY_RLS",
    role: "anon",
    targetType: "TABLE",
    targetName: "bookings",
    action: "INSERT",
    payload: { slot_id: 42, user_id: "parishioner-uuid-0001", status: "CONFIRMED" },
    expectedOutcome: "PERMISSION_DENIED",
  };

  const results: ExecutionResult[] = [
    {
      vector,
      httpStatus: 201,
      success: true,
      data: [{ id: 1, slot_id: 42 }],
      error: null,
      latencyMs: 15,
    },
  ];

  const findings = auditor.audit(results);
  assertEquals(findings.length, 1);
  assertEquals(findings[0].severity, "CRITICAL");
  assertEquals(findings[0].category, "RLS_VIOLATION");
});

Deno.test("AuditorAgent.audit safely ignores empty array on anon SELECT (filtered by RLS)", () => {
  const auditor = new AuditorAgent();
  const vector: TestVector = {
    id: "SEC-ANON-USERS-READ",
    title: "Anonymous SELECT on 'users' table (Must block via RLS)",
    category: "SECURITY_RLS",
    role: "anon",
    targetType: "TABLE",
    targetName: "users",
    action: "SELECT",
    payload: {},
    expectedOutcome: "PERMISSION_DENIED",
  };

  const results: ExecutionResult[] = [
    {
      vector,
      httpStatus: 200,
      success: true,
      data: [],
      error: null,
      latencyMs: 10,
    },
  ];

  const findings = auditor.audit(results);
  assertEquals(findings.length, 0);
});

Deno.test("AuditorAgent.audit flags perimeter verification bypass on integration endpoints", () => {
  const auditor = new AuditorAgent();
  const vector: TestVector = {
    id: "INT-PAYMOB-WEBHOOK-UNVERIFIED-HMAC",
    title: "Paymob webhook call with invalid HMAC (Must reject 401/403)",
    category: "INTEGRATION",
    role: "anon",
    targetType: "EDGE_FUNCTION",
    targetName: "paymob-webhook",
    action: "CALL",
    payload: { id: 99999, success: true },
    expectedOutcome: "PERMISSION_DENIED",
  };

  const results: ExecutionResult[] = [
    {
      vector,
      httpStatus: 200,
      success: true,
      data: { success: true },
      error: null,
      latencyMs: 25,
    },
  ];

  const findings = auditor.audit(results);
  assertEquals(findings.length, 1);
  assertEquals(findings[0].severity, "CRITICAL");
  assertEquals(findings[0].category, "INTEGRATION_BREAK");
});

Deno.test("AuditorAgent.generateReport formats markdown report", () => {
  const auditor = new AuditorAgent();
  const vector: TestVector = {
    id: "SEC-ANON-USERS-READ",
    title: "Anonymous SELECT on 'users' table",
    category: "SECURITY_RLS",
    role: "anon",
    targetType: "TABLE",
    targetName: "users",
    action: "SELECT",
    payload: {},
    expectedOutcome: "PERMISSION_DENIED",
  };

  const results: ExecutionResult[] = [
    {
      vector,
      httpStatus: 200,
      success: false,
      data: null,
      error: { code: "PGRST301", message: "JWT expired" },
      latencyMs: 12,
    },
  ];

  const report = auditor.generateReport(mockCatalog, results, []);
  assertEquals(typeof report, "string");
  assertEquals(report.length > 0, true);
  assertEquals(report.includes("# 🛡️ Autonomous Multi-Agent Supabase Backend Diagnostic Report"), true);
  assertEquals(report.includes("## 1. Executive Summary"), true);
  assertEquals(report.includes("## 2. Dynamic Schema & Surface Map"), true);
  assertEquals(report.includes("## 3. Security, RLS & Logic Findings"), true);
  assertEquals(report.includes("## 4. Live Vector Execution Log"), true);
});
