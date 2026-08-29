# Project: Church Platform Extensions (Specs 009, 010, 011)

## Architecture
Monorepo for Egyptian Coptic church digital platform with Supabase PostgreSQL 16 backend, Deno Edge Functions, Flutter Mobile client, and Flutter Admin web portal.
- **Data Layer**: PostgreSQL 16 with RLS enabled on all tables, `btree_gist` range exclusion constraints for priest schedules and venue reservations, client DML revoked on sensitive tables, single-rail cash/manual payments in integer piastres.
- **RPC Seam**: `SECURITY DEFINER` functions with `SET search_path = public, pg_temp;` enforcing role checks (`public.is_admin()`, `public.is_class_servant()`, or public verification).
- **Communication Layer**: PostgreSQL outbox queues (`event_outbox`, `whatsapp_outbox`) for transactional notifications.
- **Storage Layer**: Supabase Storage private buckets (`certificates`) with strict RLS on `storage.objects`.
- **Client Presentation**: Flutter Mobile (Family Archive, Servant Attendance Portal, Booking details) and Flutter Admin (Allocation Matrix Calendar, Sacramental Registrar, Sunday School Dashboard).

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Priest Schedule Schema & Exclusion | `priest_schedules` table with `btree_gist` range exclusion on `(priest_id, schedule_range)` | M1 | Spec 009 |
| 2 | Event Booking Priest Assignment | `assigned_priest_id` on `event_bookings` with GiST exclusion constraint on `(assigned_priest_id, booking_range)` | M1 | Spec 009 |
| 3 | Atomic Priest & Venue Allocation RPC | `admin_assign_priest_and_venue` RPC validating availability, updating booking, syncing schedule, logging audit, enqueuing WhatsApp | M1 | Spec 009 |
| 4 | Priest Availability Filter RPC | `get_available_priests(p_start_time, p_end_time)` STABLE query excluding conflicted clergy | M1 | Spec 009 |
| 5 | Admin Allocation Matrix Calendar | Flutter Admin visual schedule calendar (`/allocation-matrix`) and priest/venue assignment dialog | M1 | Spec 009 |
| 6 | Mobile Booking Priest Details | Mobile booking ticket displaying assigned priest name and details | M1 | Spec 009 |
| 7 | Sacramental Records Schema | `sacramental_records` immutable table with token, sacrament types, client DML revoked | M2 | Spec 010 |
| 8 | Private Certificates Storage Bucket | `certificates` private bucket with RLS on `storage.objects` for certificate PDFs | M2 | Spec 010 |
| 9 | Issue Sacramental Certificate RPC | `issue_sacramental_certificate` admin-only RPC generating secure verification tokens | M2 | Spec 010 |
| 10 | Public QR Verification RPC | `verify_certificate(p_token)` public privacy-preserving verification RPC returning sanitized metadata | M2 | Spec 010 |
| 11 | Revoke Sacramental Certificate RPC | `admin_revoke_certificate(p_record_id, p_reason)` admin RPC | M2 | Spec 010 |
| 12 | Admin Sacramental Registrar | Flutter Admin registrar screen (`/sacramental-records`), issuance form, certificate preview | M2 | Spec 010 |
| 13 | Mobile Family Digital Archive | Flutter Mobile family profile tab displaying digital certificates & QR verification viewer | M2 | Spec 010 |
| 14 | Sunday School Hierarchy Schema | `sunday_school_classes`, `sunday_school_servants`, `sunday_school_students`, `sunday_school_sessions`, `sunday_school_attendance` | M3 | Spec 011 |
| 15 | Attendance Uniqueness Constraint | `UNIQUE (student_id, session_date)` enforcing one attendance entry per student per session | M3 | Spec 011 |
| 16 | Bulk Attendance Recording RPC | `record_bulk_attendance` atomic RPC gated by `is_admin() OR is_class_servant(p_class_id)` | M3 | Spec 011 |
| 17 | Mobile Servant Attendance Portal | Mobile servant screen for attendance taking with offline queue sync integration | M3 | Spec 011 |
| 18 | Admin Sunday School Dashboard | Flutter Admin dashboard (`/sunday-school`) for class management, servant assignments, attendance analytics | M3 | Spec 011 |
| 19 | E2E Regression & Quality Gate | 100% test pass on SQL (`node scripts/test-sql.js`), Deno (`deno test`), Mobile & Admin (`flutter test`) | M4 | System Invariant |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Spec 009: Smart Priest & Hall Allocation | `0075_priest_hall_allocation.sql`, tests, Admin Calendar, Mobile Booking | None | DONE |
| M2 | Spec 010: Sacramental Records Archive | `0076_sacramental_records.sql`, tests, Admin Registrar, Mobile Family Archive | M1 | DONE |
| M3 | Spec 011: Servants & Sunday School | `0077_sunday_school_management.sql`, tests, Mobile Servant Portal, Admin Dashboard | M1 | DONE |
| M4 | Final E2E Test Pass & Forensic Audit | Full test suites run (SQL, Deno, Flutter), adversarial verification, forensic audit | M1, M2, M3 | IN_PROGRESS |

## Interface Contracts
### Spec 009 Contracts
- `admin_assign_priest_and_venue(p_booking_id UUID, p_venue_id UUID, p_priest_id BIGINT, p_override_notes TEXT DEFAULT NULL) RETURNS JSONB`
- `get_available_priests(p_start_time TIMESTAMPTZ, p_end_time TIMESTAMPTZ) RETURNS TABLE (id BIGINT, name TEXT, photo_url TEXT, phone TEXT, rank TEXT, active_bookings_count BIGINT)`
- Errors: `{"error": "FORBIDDEN", "message_ar": "..."}`, `{"error": "VENUE_UNAVAILABLE", ...}`, `{"error": "PRIEST_UNAVAILABLE", ...}`

### Spec 010 Contracts
- `issue_sacramental_certificate(p_sacrament_type TEXT, p_recipient_name_ar TEXT, p_recipient_national_id TEXT, p_recipient_user_id UUID, p_sacrament_date DATE, p_officiating_priest_id BIGINT, p_church_location_ar TEXT, p_registry_book_number TEXT, p_registry_page_number TEXT, p_registry_entry_number TEXT, p_godparents_ar TEXT DEFAULT NULL, p_notes TEXT DEFAULT NULL, p_pdf_storage_path TEXT DEFAULT NULL) RETURNS JSONB`
- `verify_certificate(p_token TEXT) RETURNS JSONB` (Privacy preserving: returns `is_valid`, `sacrament_type`, `recipient_name_ar`, `sacrament_date`, `officiating_priest_name`, `church_location_ar`, `status`, `issued_at`, omits national ID and user ID)
- `admin_revoke_certificate(p_record_id UUID, p_reason TEXT) RETURNS JSONB`

### Spec 011 Contracts
- `record_bulk_attendance(p_class_id UUID, p_session_date DATE, p_records JSONB, p_session_title TEXT DEFAULT NULL) RETURNS JSONB`
- `is_class_servant(p_class_id UUID) RETURNS BOOLEAN`
- Errors: `{"error": "FORBIDDEN", "message_ar": "غير مصرح لك بتسجيل الحضور لهذا الفصل"}`, `{"error": "BAD_REQUEST", ...}`

## Code Layout
- `supabase/migrations/0075_priest_hall_allocation.sql`
- `supabase/migrations/0076_sacramental_records.sql`
- `supabase/migrations/0077_sunday_school_management.sql`
- `supabase/tests/0075_priest_hall_allocation_test.sql`
- `supabase/tests/0076_sacramental_records_test.sql`
- `supabase/tests/0077_sunday_school_management_test.sql`
- `supabase/tests/run_all.sql`
- `apps/admin/lib/features/allocation/`
- `apps/admin/lib/features/sacraments/`
- `apps/admin/lib/features/sunday_school/`
- `apps/mobile/lib/features/family_archive/`
- `apps/mobile/lib/features/sunday_school/`
