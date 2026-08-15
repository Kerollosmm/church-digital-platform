-- 0012: payments.merchant_order_id + apply_payment (webhook landing)
alter table public.payments add column if not exists merchant_order_id text;

-- status enum extension: REFUND_PENDING marks a payment waiting for the event-dispatcher edge fn
alter type public.payment_status add value if not exists 'REFUND_PENDING';

-- idempotency key per conventions: gateway_ref unique (NULLs allowed for CREATED rows)
create unique index if not exists uq_payments_gateway_ref
  on public.payments (gateway_ref) where gateway_ref is not null;

create or replace function public.apply_payment(p_payment_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_pay public.payments;
  v_book public.bookings;
  v_phone text;
begin
  select * into v_pay from public.payments where id = p_payment_id for update;
  if v_pay is null then raise exception 'PAYMENT_NOT_FOUND'; end if;
  if v_pay.status = 'PAID' then return; end if;  -- idempotent
  update public.payments set status = 'PAID' where id = v_pay.id;
  if v_pay.booking_id is not null then
    select * into v_book from public.bookings where id = v_pay.booking_id for update;
    -- late webhook: booking already cancelled/lock expired -> never grant the seat, auto-refund
    if v_book is null
       or v_book.status <> 'PENDING_PAYMENT'
       or v_book.locked_until <= now() then
      update public.payments set status = 'REFUND_PENDING' where id = v_pay.id;
      if not exists (select 1 from public.event_outbox where handler_type = 'PAYMOB_REFUND' and payload->>'payment_id' = v_pay.id::text) then
        insert into public.event_outbox (handler_type, payload)
        values ('PAYMOB_REFUND', jsonb_build_object('payment_id', v_pay.id, 'amount', v_pay.amount));
      end if;

      return;
    end if;
    update public.bookings set paid_amount = v_pay.amount where id = v_book.id;
    v_book := public.transition_booking_status(v_book.id, 'AWAITING_CALL', 'apply_payment', null, jsonb_build_object('payment_id', v_pay.id));
    select phone into v_phone from public.users where id = v_book.user_id;
    if v_phone is not null and not exists (
      select 1 from public.event_outbox
      where handler_type = 'WHATSAPP'
        and (payload->>'booking_id' = v_book.id::text or payload->'params'->>'booking_id' = v_book.id::text)
        and payload->>'template_name' = 'booking_payment_received'
    ) then
      insert into public.event_outbox (handler_type, payload)
      values ('WHATSAPP', jsonb_build_object('phone', v_phone, 'template_name', 'booking_payment_received',
                                             'params', jsonb_build_object('booking_id', v_book.id, 'amount', v_pay.amount)));
    end if;
  end if;

end $$;

