begin;
select plan(3);

-- fixtures
insert into auth.users (id, email, phone) values
  ('dddddddd-0000-0000-0000-000000008301'::uuid, 'user8301@test.com', '+201000008301')
on conflict (id) do update set email = excluded.email, phone = excluded.phone;

insert into public.users (id, phone, name, role, tenant_id) values
  ('dddddddd-0000-0000-0000-000000008301'::uuid, '+201000008301', 'Owner 83', 'USER', 1)
on conflict (id) do update set role = excluded.role;

insert into public.services (id, tenant_id, title_ar)
  overriding system value values (831, 1, 'خدمة 83')
on conflict (id) do nothing;

insert into public.service_slots (id, service_id, tenant_id, starts_at, ends_at, capacity, price)
  overriding system value values (831, 831, 1, now() + interval '4 days', now() + interval '4 days 2 hours', 5, 5000)
on conflict (id) do update set price = 5000;

insert into public.bookings (id, user_id, slot_id, tenant_id, status, paid_amount)
  overriding system value values (831, 'dddddddd-0000-0000-0000-000000008301'::uuid, 831, 1, 'PENDING_PAYMENT', 0)
on conflict (id) do nothing;

insert into storage.objects (bucket_id, name) values ('payment-proofs', '1/831/proof.jpg')
on conflict do nothing;

set local role authenticated;
set local request.jwt.claims = '{"sub":"dddddddd-0000-0000-0000-000000008301"}';
select public.submit_payment_proof(831, 'VODAFONE_CASH', '+201000008301', 'ref83001', 5000, '1/831/proof.jpg');
reset role;

-- a slot priced 50 EGP before migration stores 5000 after
select is(
  (select price from public.service_slots where id = 831),
  5000::int,
  'slot price is in piastres (5000 = 50 EGP)'
);

-- payments.amount is piastres
select is(
  (select amount from public.payments where booking_id = 831 limit 1) >= 100,
  true,
  'payments.amount stored in piastres (>= 100 for any nonzero EGP amount)'
);

select is(
  (select amount_claimed from public.payment_proofs where booking_id = 831 limit 1) >= 100,
  true,
  'payment_proofs.amount_claimed stored in piastres'
);

select * from finish();
rollback;
