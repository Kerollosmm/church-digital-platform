-- supabase/tests/0066_manual_payment_foundations_test.sql
-- 011 Phase 2 foundations: payment_channel enum, payment_proofs CHECKs +
-- one-PENDING-per-booking index, RLS ownership reads, payout_channels tier
-- gates, seed idempotency, identity sequence grant.

begin;
select plan(16);

-- ---------------------------------------------------------------- fixtures
delete from public.payment_proofs where booking_id in (661, 662);
delete from public.bookings where id in (661, 662);
delete from public.service_slots where id in (661);
delete from public.services where id in (661);

insert into auth.users (id, email, phone) values
  ('cccccccc-0000-0000-0000-000000006601'::uuid, 'user6601@test.com', '+201000006601'),
  ('cccccccc-0000-0000-0000-000000006602'::uuid, 'user6602@test.com', '+201000006602')
on conflict (id) do update set email = excluded.email, phone = excluded.phone;

insert into public.users (id, phone, name, role, tenant_id) values
  ('cccccccc-0000-0000-0000-000000006601'::uuid, '+201000006601', 'Owner', 'USER', 1),
  ('cccccccc-0000-0000-0000-000000006602'::uuid, '+201000006602', 'Other', 'USER', 1)
on conflict (id) do update set role = excluded.role;

insert into public.services (id, tenant_id, title_ar)
  overriding system value values (661, 1, 'قداس');
insert into public.service_slots (id, service_id, tenant_id, starts_at, ends_at, capacity)
  overriding system value values (661, 661, 1, now() + interval '3 days', now() + interval '3 days 2 hours', 5);
insert into public.bookings (id, user_id, slot_id, tenant_id, status)
  overriding system value values (661, 'cccccccc-0000-0000-0000-000000006601'::uuid, 661, 1, 'PENDING_PAYMENT');

-- ------------------------------------------------- 1: enum surface
select set_eq(
  $$ select e.enumlabel from pg_enum e join pg_type t on t.oid = e.enumtypid where t.typname = 'payment_channel' $$,
  array['VODAFONE_CASH', 'INSTAPAY', 'CASH'],
  'payment_channel enum has exactly the three manual-rail channels'
);

-- ------------------------------------------------- 2..4: table CHECKs
select throws_ok(
  $$ insert into public.payment_proofs (booking_id, channel, sender_phone, reference_number, amount_claimed, image_path)
     values (661, 'VODAFONE_CASH', '+201000006601', 'ref661a', 100, null) $$,
  '23514', null,
  'wallet proof without image_path rejected by CHECK'
);

select throws_ok(
  $$ insert into public.payment_proofs (booking_id, channel, sender_phone, reference_number, amount_claimed, image_path)
     values (661, 'CASH', '+201000006601', 'receipt661', 100, '1/661/x.jpg') $$,
  '23514', null,
  'CASH proof carrying an image rejected by CHECK'
);

select throws_ok(
  $$ insert into public.payment_proofs (booking_id, channel, sender_phone, reference_number, amount_claimed, image_path, status)
     values (661, 'CASH', '+201000006601', 'receipt661', 100, null, 'REJECTED') $$,
  '23514', null,
  'REJECTED proof without reason code rejected by CHECK'
);

-- ------------------------------------------------- 5..6: one PENDING per booking
insert into public.payment_proofs (booking_id, channel, sender_phone, reference_number, amount_claimed, image_path)
values (661, 'INSTAPAY', '+201000006601', 'ref661ok', 150, '1/661/proof.jpg');

select throws_ok(
  $$ insert into public.payment_proofs (booking_id, channel, sender_phone, reference_number, amount_claimed, image_path)
     values (661, 'VODAFONE_CASH', '+201000006601', 'ref661dup', 150, '1/661/dup.jpg') $$,
  '23505', null,
  'second PENDING proof for same booking rejected by partial unique index'
);

-- ------------------------------------------------- 7..9: RLS ownership reads
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000006601"}';
select is(
  (select count(*) from public.payment_proofs where booking_id = 661), 1::bigint,
  'owner reads the proof on their own booking'
);

set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000006602"}';
select is(
  (select count(*) from public.payment_proofs where booking_id = 661), 0::bigint,
  'non-owner member sees zero proofs on someone else''s booking'
);
reset role;

set local role anon;
select is(
  (select count(*) from public.payment_proofs where booking_id = 661), 0::bigint,
  'anon sees zero payment proofs'
);
reset role;

-- ------------------------------------------------- 10: clients cannot write proofs directly
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000006601"}';
select throws_ok(
  $$ insert into public.payment_proofs (booking_id, channel, sender_phone, reference_number, amount_claimed, image_path)
     values (661, 'CASH', '+201000006601', 'direct', 50, null) $$,
  '42501', null,
  'authenticated direct INSERT into payment_proofs denied (RPC-only writes)'
);
reset role;

-- ------------------------------------------------- 11..13: payout_channels tiers
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000006601"}';
select is(
  (select count(*) from public.payout_channels), 2::bigint,
  'authenticated reads seeded payout channels (both wallets)'
);
reset role;

update public.users set role = 'ADMIN' where id = 'cccccccc-0000-0000-0000-000000006602'::uuid;
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000006602"}';
update public.payout_channels set account_number = 'hacked' where channel = 'INSTAPAY';
select is(
  (select account_number from public.payout_channels where channel = 'INSTAPAY'), '01011112222',
  'ADMIN payout UPDATE affects zero rows (tier gate)'
);
reset role;

update public.users set role = 'SUPER_ADMIN' where id = 'cccccccc-0000-0000-0000-000000006602'::uuid;
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-0000-0000-0000-000000006602"}';
update public.payout_channels set account_number = '01099998888' where channel = 'INSTAPAY';
select is(
  (select account_number from public.payout_channels where channel = 'INSTAPAY'), '01099998888',
  'SUPER_ADMIN payout UPDATE lands'
);
reset role;
update public.users set role = 'USER' where id = 'cccccccc-0000-0000-0000-000000006602'::uuid;

-- ------------------------------------------------- 14..15: seed idempotency structure
insert into public.payout_channels (channel, display_name_ar, account_number, holder_name)
values ('VODAFONE_CASH', 'فودافون كاش', '01000000000', 'الكنيسة')
on conflict (channel) do update set display_name_ar = excluded.display_name_ar;

select is(
  (select count(*) from public.payout_channels where channel = 'VODAFONE_CASH'), 1::bigint,
  're-running the seed upsert keeps exactly one row per wallet channel'
);

select ok(
  exists (
    select 1 from pg_constraint c
    where c.conrelid = 'public.payout_channels'::regclass
      and c.contype = 'u' and array_to_string(c.conkey, ',') = (
        select array_to_string(array_agg(attnum order by attnum), ',')
        from pg_attribute
        where attrelid = 'public.payout_channels'::regclass and attname = 'channel')
  ),
  'payout_channels.channel carries a unique constraint (seed idempotent by construction)'
);

-- ------------------------------------------------- 16: identity sequence grant
select ok(
  has_sequence_privilege('authenticated', 'public.payment_proofs_id_seq', 'USAGE, SELECT'),
  'authenticated may draw from payment_proofs_id_seq'
);

select * from finish();
rollback;
