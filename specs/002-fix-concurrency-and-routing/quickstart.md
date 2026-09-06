# Quickstart Validation Guide: Platform Hardening & Bug Fixes

## 1. Database Migrations & Concurrency Tests
```bash
# Push migrations to local Supabase
npx supabase db reset

# Run all backend SQL tests
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/0035_concurrency_atomic_test.sql
```

## 2. Edge Functions Validation
```bash
# Test all Edge Functions including Paymob HMAC and YouTube Expiry
cd supabase/functions
deno test --allow-env --allow-net
```

## 3. Mobile App Validation
```bash
# Run Flutter unit and widget tests
cd apps/mobile
flutter test
```

## 4. Admin Web App Validation
```bash
# Run Flutter admin router and widget tests
cd apps/admin
flutter test
```