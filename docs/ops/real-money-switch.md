# Real-Money Switch Checklist (Free -> live Paymob)

## Preconditions (all must be checked)
- [ ] Paymob merchant account KYC complete; integration live (not sandbox).
- [ ] WhatsApp Business verified; all 8 templates APPROVED by Meta (booking_confirmed, payment_received, booking_cancelled, booking_rescheduled, booking_apology, otp_auth, booking_payment_received, booking_offer).
- [ ] Supabase Pro (or confirmed Free-tier headroom): 500k edge invocations/mo, 5GB egress.
- [ ] Play internal testing passed (docs/ops/play-internal-testing.md).

## Switch steps
1. Set live secrets: `supabase secrets set PAYMOB_API_KEY=<live> PAYMOB_PUBLIC_KEY=<live> PAYMOB_INTEGRATION_ID=<live> PAYMOB_HMAC_KEY=<live> WHATSAPP_TOKEN=<prod> WHATSAPP_PHONE_ID=<prod>`.
2. Point apps to prod project: `--dart-define=SUPABASE_URL=$PROD_URL --dart-define=SUPABASE_ANON_KEY=$PROD_ANON`.
3. `supabase db push --db-url $PROD_DB_URL` (all migrations 0001-0020) then run Task 16 ops step (vault secrets SUPABASE_URL + SERVICE_ROLE_KEY).
4. Deploy edge functions: `supabase functions deploy --project-ref $PROD_REF`.
5. Register webhook in Paymob dashboard → prod edge URL `/functions/v1/paymob-webhook` and set the same `PAYMOB_HMAC_KEY` there (digest arrives as the `?hmac=` query param on callbacks).
6. Point cron jobs: verify `cron.job` rows in prod (expire-bookings, whatsapp-drain, refund-drain, reconcile-payments).
7. Dry-run with one priest: book (real EGP 1 test slot) → pay Vodafone Cash → confirm → WhatsApp.
8. Verify refund path: emergency_override with refund on the test booking → Paymob dashboard shows refund within 2 min.
9. Archive the sandbox checkout URL in staging; keep staging for e2e only.
