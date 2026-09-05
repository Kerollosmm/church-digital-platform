-- 0083: unify legacy slot-domain money into integer piastres
-- (project invariant: 1 EGP = 100 piastres, all money integer piastres)
-- Event-booking domain (0073+) already stores piastres.

begin;

-- Data conversion (idempotency is NOT possible here: 0083 runs exactly once
-- per replay. Value 0 rows are safe under multiplication.)
update public.service_slots       set price          = price * 100;
update public.bookings            set paid_amount    = paid_amount * 100;
update public.payments            set amount         = amount * 100;
update public.payment_proofs      set amount_claimed = amount_claimed * 100;

commit;
