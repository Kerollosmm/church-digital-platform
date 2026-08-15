# Verification Runbook

## 1. Automated Test Execution

```bash
# Admin Web test suite (Auth, Router Guard, Screens)
cd apps/admin
flutter test

# Parishioner Mobile test suite (Home Navigation, BottomNav, PhoneGate)
cd ../mobile
flutter test

# Deno Edge Functions (OTP, Webhook HMAC, Outbox)
cd ../../supabase/functions
deno test --allow-env --allow-net

# Backend DB Regression
cd ..
psql $DATABASE_URL -f tests/run_all.sql