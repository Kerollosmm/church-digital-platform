# Church Digital Platform

Single Egyptian Coptic church: parishioner app + admin dashboard + booking/payment engine
(Paymob wallets & Visa) + WhatsApp automation + confirmation-call booking flow (admin approves
each booking after calling) + analytics.

Stack: Flutter (mobile + web admin) · Supabase (PostgreSQL 16, Auth phone OTP, RLS, Edge
Functions) · Paymob · WhatsApp Cloud API.

Layout:
- `apps/mobile` — Flutter app (parishioners + servants, Android/iOS)
- `apps/admin` — Flutter Web PWA (employees, priests, super admins)
- `supabase/migrations` — ordered SQL migrations (Phase 0 owns 0001–0003; later phases 0004+)
- `supabase/tests` — psql regression tests (run via `run_all.sql`)
- `supabase/functions` — Deno Edge Functions (shared auth/error kernel in `_shared/`)
- `supabase/seed.sql` — demo data (users, services, priests, FAQ)
- `docs/` — `conventions.md` (living rules), `adr/` (decision records), onboarding checklist
- `specs/` — speckit feature specs (003 edge kernel, 004 accessibility + video delivery, 005 admin, 006 mobile)
- `.github/workflows` — CI (flutter analyze/test, SQL tests, deno test, staging deploy)

Local dev: `supabase start` (Docker), `supabase db reset`, then
`psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/run_all.sql`.
Full conventions: `docs/superpowers/plans/conventions.md`.
