import { assertEquals, assertNotEquals } from "jsr:@std/assert";
import {
  createPendingPayment,
  markPaymentFailed,
  recordPaidPayment,
} from "../_shared/payments-gateway.ts";

type RpcCall = { fn: string; params: Record<string, unknown> };

function stubClient(calls: RpcCall[]) {
  return {
    rpc(fn: string, params?: Record<string, unknown>) {
      calls.push({ fn, params: params ?? {} });
      return Promise.resolve({ data: null, error: null });
    },
    from(_table: string) {
      throw new Error("direct table access forbidden in payments-gateway");
    },
  };
}

Deno.test("gateway: createPendingPayment calls create_pending_payment RPC", async () => {
  const calls: RpcCall[] = [];
  const res = await createPendingPayment(stubClient(calls) as never, {
    bookingId: 901,
    amount: 150,
    gatewayRef: "txn_new",
  });

  assertEquals(res.ok, true);
  assertEquals(calls.length, 1);
  assertEquals(calls[0].fn, "create_pending_payment");
  assertEquals(calls[0].params, {
    p_booking_id: 901,
    p_amount: 150,
    p_gateway_ref: "txn_new",
  });
});

Deno.test("gateway: markPaymentFailed calls mark_payment_failed RPC", async () => {
  const calls: RpcCall[] = [];
  const res = await markPaymentFailed(stubClient(calls) as never, 99981);

  assertEquals(res.ok, true);
  assertEquals(calls.length, 1);
  assertEquals(calls[0].fn, "mark_payment_failed");
  assertEquals(calls[0].params, { p_payment_id: 99981, p_detail: null });
});

Deno.test("gateway: recordPaidPayment calls apply_payment RPC", async () => {
  const calls: RpcCall[] = [];
  const res = await recordPaidPayment(stubClient(calls) as never, 99982);

  assertEquals(res.ok, true);
  assertEquals(calls.length, 1);
  assertEquals(calls[0].fn, "apply_payment");
  assertEquals(calls[0].params, { p_payment_id: 99982 });
});

Deno.test("gateway: RPC error surfaces as failure result with frozen code", async () => {
  const failing = {
    rpc() {
      return Promise.resolve({
        data: null,
        error: { message: "INVALID_STATUS: booking is not pending payment" },
      });
    },
    from() {
      throw new Error("direct table access forbidden");
    },
  };
  const res = await markPaymentFailed(failing as never, 1);
  assertNotEquals((res as { ok?: boolean }).ok, true);
});
