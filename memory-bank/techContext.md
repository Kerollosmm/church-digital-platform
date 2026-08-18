# Tech Context: Church Digital Platform

## Technology Stack

### Frontend & Clients
- **Mobile App**: Flutter 3.x / Dart 3.x (`apps/mobile/`)
  - Target: Android (primary), iOS
  - State: `flutter_riverpod` (v2.x)
  - Navigation: `go_router` (v14.x)
  - Backend Client: `supabase_flutter` (v2.x)
  - Layout: Arabic RTL, `google_fonts` (Cairo/Tajawal), responsive MediaQuery/LayoutBuilder
- **Admin Dashboard**: Flutter Web PWA (`apps/admin/`)
  - State & Navigation: `flutter_riverpod`, `go_router`
  - Data Visualization: `fl_chart`
  - Security: Multi-step Admin Login (Phone OTP + Memorized PIN 2FA)

### Backend & Database
- **Database Engine**: PostgreSQL 16 (via Supabase Docker container `supabase_db_church`)
  - Extensions: `pgcrypto`, `btree_gist`, `pg_cron`, `pg_net`, `pg_graphql`, `dblink` (in test suite schema `dblink_test`)
  - Security: Row Level Security (RLS) enabled on 100% of tables
  - Identity & Sequences: Bigint sequences granted to `authenticated` where client inserts are authorized
- **Edge Runtime**: Deno / TypeScript (`supabase/functions/`)
  - Deno standard library + Supabase JS SDK (`@supabase/supabase-js`)
  - JWT verification & role authorization
- **Third-Party Gateways**:
  - **Paymob**: Intention & checkout iframe/mobile wallet API; webhook HMAC SHA-512 verification
  - **Meta Cloud API**: WhatsApp Business Graph API for transactional message templates
  - **Google Firebase**: FCM v1 HTTP API with OAuth2 bearer token exchange for push notifications

## Development & Test Execution Workflows

### 1. Database Migrations & Resets
```bash
# Reset database and replay all migrations 0001 -> 0053 + seed.sql
npx supabase db reset
```

### 2. SQL Test Suites (pgTAP via Stdin)
> [!IMPORTANT]
> The `supabase/tests/` directory is **not** mounted inside the container, and `run_all.sql` cannot be piped directly over stdin because relative `\ir` paths do not resolve.
> Always pipe SQL suites individually over stdin to `supabase_db_church`:

```bash
# Run a single suite
docker exec -i supabase_db_church psql -U postgres -d postgres < supabase/tests/0053_security_fixes_test.sql

# Automated verification rule:
# Grep stdout for 'not ok' and '# Looks like you failed'. Do NOT rely on psql exit code alone!
```

### 3. Edge Function Unit Tests
```bash
# Run all Deno tests across all edge functions
deno test --allow-env --allow-net supabase/functions/
```

### 4. Flutter Mobile & Admin App Verification
```bash
# Mobile tests
cd apps/mobile
flutter analyze
flutter test

# Admin tests
cd apps/admin
flutter analyze
flutter test
```

## Environmental Quirks & Port Mappings
1. **Kong Host Port**: Published at `http://127.0.0.1:53321` on the local host (not `54321`).
2. **Postgres Connection**: `postgresql://postgres:postgres@127.0.0.1:54322/postgres`.
3. **CRLF Line Endings**: Windows CRLF endings can break piped scripts; strip `\r` when reading file lists.
4. **pgTAP Exit Codes**: `psql` exits with code 0 even when pgTAP assertions fail; test runners must parse output for failure markers.
