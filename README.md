# Church Digital Platform

Single Egyptian Coptic church: parishioner app + admin dashboard + booking/payment engine
(Paymob) + WhatsApp automation + paid video access + servants/visitation management (CMeeting
replacement) + analytics.

Stack: Flutter (mobile + web admin) · Supabase (PostgreSQL 16, Auth phone OTP, RLS, Edge
Functions) · Paymob · WhatsApp Cloud API · YouTube unlisted videos.

Layout:
- `apps/mobile` — Flutter app (parishioners + servants, Android/iOS)
- `apps/admin` — Flutter Web PWA (employees, priests, super admins)
- `supabase/migrations` — ordered SQL migrations (Phase 0 owns 0001–0003; Phase 1 uses 0004+)
- `supabase/tests` — psql DO-block regression tests
- `supabase/functions` — Deno Edge Functions
- `supabase/seed.sql` — demo data (users, services, priests, FAQ)
- `.github/workflows` — CI (flutter analyze/test, SQL tests, deno test, staging deploy)
- `docs/superpowers/plans` — plan documents (master blueprint + per-phase plans)

Local dev: `supabase start` (Docker), `supabase db reset`, then
`psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/run_all.sql`.
Full conventions: `docs/superpowers/plans/conventions.md`.
