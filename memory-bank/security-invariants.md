# Security Invariants & Architecture Guardrails

## 1. Database Privilege Hardening
- **SECURITY DEFINER Functions**:
  - Every restricted function must revoke all execution privileges from `PUBLIC`, `anon`, and `authenticated`.
  - Grants must be granular and explicit:
    ```sql
    REVOKE ALL ON FUNCTION public.<name>(<args>) FROM PUBLIC, anon, authenticated;
    GRANT EXECUTE ON FUNCTION public.<name>(<args>) TO service_role; -- or authenticated
    ```
  - Functions must always specify `SET search_path = public, pg_temp;` to prevent search_path hijacking.

## 2. Row Level Security (RLS) Rules
- **RLS Mandatory on All Tables**:
  ```sql
  ALTER TABLE public.<table_name> ENABLE ROW LEVEL SECURITY;
  ```
- **Tenant Check Invariant**:
  - Every table policy must include `tenant_id = public.tenant_id()`.
- **Admin Access Check**:
  - Admin mutation policies must check `public.is_admin()`.
  - Target roles explicitly (`TO authenticated` or `TO anon, authenticated`).
  - Never use `GRANT ALL` in migrations; grant explicit `SELECT, INSERT, UPDATE, DELETE`.
- **Financial Table Isolation**:
  - `payments`, `complaints`, `audit_log`, `roles_permissions` must NEVER have permissive `FOR ALL` policies attached to `authenticated`.
  - Client reads occur through secured views or restricted RPCs. Client writes occur exclusively via RPCs.

## 3. Storage Bucket Policies
- Any migration provisioning or altering storage buckets must include:
  ```sql
  ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
  ```
- Grants on `storage.objects` must be granular (`SELECT, INSERT, UPDATE, DELETE TO authenticated`), never `GRANT ALL`.

## 4. Payment Gateway & Webhook Security
- **HMAC Verification**:
  - Paymob webhooks must be verified against `PAYMOB_HMAC_KEY` using constant-time cryptographic comparison before processing any payload.
- **Idempotency**:
  - Webhooks must check whether payment status is already `PAID` or `REFUNDED` and exit idempotently without duplicate triggers or outbox events.
- **Positive Integer Validation**:
  - Amounts from webhooks must be strictly positive integers matching database expectation in piastres.
- **Service-Role Only Confirmation**:
  - `apply_payment` cannot be executed by client JWTs; only edge functions using `service_role` can confirm payments.

## 5. Edge Function Auth Perimeter
- **JWT Authorization**:
  - All non-webhook edge functions must validate the `Authorization: Bearer <JWT>` header.
- **Direct Role Resolution**:
  - Roles must be resolved directly from `public.users.role` in PostgreSQL using service-role queries, never relying on JWT claims or metadata.
- **Zero-Leak Error Responses**:
  - All internal 500 errors must return sanitized JSON `{"error": "INTERNAL", "message_ar": "..."}` without stack traces or exception payloads.
