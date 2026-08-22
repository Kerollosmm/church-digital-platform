import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

// Single sanctioned write seam for the payments table (AGENTS.md money
// boundary): every integration-side payment state change goes through a
// SECURITY DEFINER RPC via this module. No code outside this file may call
// .from("payments") for writes.

export interface GatewayResult<T = unknown> {
  ok: boolean;
  data?: T;
  errorCode?: string;
}

function fail<T>(error: { message?: string; code?: string } | null): GatewayResult<T> {
  return { ok: false, errorCode: error?.code ?? "INTERNAL" };
}

export async function createPendingPayment(
  client: SupabaseClient,
  opts: { bookingId: number; amount: number; gatewayRef?: string | null },
): Promise<GatewayResult<number>> {
  const { data, error } = await client.rpc("create_pending_payment", {
    p_booking_id: opts.bookingId,
    p_amount: opts.amount,
    p_gateway_ref: opts.gatewayRef ?? null,
  });
  if (error) return fail(error);
  return { ok: true, data: data as number };
}

export async function markPaymentFailed(
  client: SupabaseClient,
  paymentId: number,
  detail?: Record<string, unknown>,
): Promise<GatewayResult<void>> {
  const { error } = await client.rpc("mark_payment_failed", {
    p_payment_id: paymentId,
    p_detail: detail ?? null,
  });
  if (error) return fail(error);
  return { ok: true };
}

export async function recordWebhookPayment(
  client: SupabaseClient,
  opts: {
    merchantOrderId: string;
    gatewayRef: string;
    amount: number;
    paid: boolean;
    raw: unknown;
  },
): Promise<GatewayResult<{ id: number; already_paid: boolean }>> {
  const { data, error } = await client.rpc("record_webhook_payment", {
    p_merchant_order_id: opts.merchantOrderId,
    p_gateway_ref: opts.gatewayRef,
    p_amount: opts.amount,
    p_paid: opts.paid,
    p_raw: opts.raw,
  });
  if (error) return fail(error);
  return { ok: true, data: data as { id: number; already_paid: boolean } };
}

export async function recordPaidPayment(
  client: SupabaseClient,
  paymentId: number,
): Promise<GatewayResult<void>> {
  const { error } = await client.rpc("apply_payment", {
    p_payment_id: paymentId,
  });
  if (error) return fail(error);
  return { ok: true };
}

export type PaymentChannel = "VODAFONE_CASH" | "INSTAPAY" | "CASH";

export async function submitPaymentProof(
  client: SupabaseClient,
  opts: {
    bookingId: number;
    channel: PaymentChannel;
    senderPhone: string;
    reference: string;
    amount: number;
    imagePath?: string | null;
  },
): Promise<GatewayResult<number>> {
  const { data, error } = await client.rpc("submit_payment_proof", {
    p_booking_id: opts.bookingId,
    p_channel: opts.channel,
    p_sender_phone: opts.senderPhone,
    p_reference: opts.reference,
    p_amount: opts.amount,
    p_image_path: opts.imagePath ?? null,
  });
  if (error) return fail(error);
  return { ok: true, data: data as number };
}
