# Church Hub — Phase 1 Schema & Architecture Reconciliation

## 1. Executive Summary & Authoritative Hierarchy

This document formally reconciles the backend plan specifications with the live PostgreSQL 16 schema in the repository.

### Authoritative Hierarchy Rules
1. **Live Migrations are Authoritative**: The numbered SQL migrations in `supabase/migrations/` (`0001` through `0041`) define the active source of truth for existing database tables, columns, constraints, RLS policies, RPC signatures, and views.
2. **Backend Plans are Authoritative Only for NEW Features**: Plans specify incoming functional requirements (e.g., social links, clergy directory extensions) but must adapt to the live schema conventions without introducing breaking changes, renaming existing tables, or altering entity ID strategies.

---

## 2. Live Schema Contracts Summary

### 2.1 Identity & RBAC
- **Roles Enum (`public.app_role`)**: Post-migration `0033_collapse_roles.sql`, the enum strictly contains `('USER', 'ADMIN')`. Deprecated roles (`PARISHIONER`, `PRIEST`, `SUPER_ADMIN`) have been removed from the database and restricted in client router guards.
- **User Table (`public.users`)**: Keyed on `id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE`. Contains `phone TEXT UNIQUE`, `name TEXT`, `role public.app_role DEFAULT 'USER'`, `fcm_token TEXT`, and `tenant_id BIGINT`.
- **RBAC Helpers**:
  - `public.current_user_role()` -> `TEXT` ('USER' | 'ADMIN' | 'anon')
  - `public.is_admin()` -> `BOOLEAN` (`current_user_role() = 'ADMIN'`)
  - `public.tenant_id()` -> `BIGINT` (resolved from `public.users` or JWT claim)

### 2.2 Domain Entities & ID Types
All domain entity tables strictly utilize `BIGINT generated always as identity` primary keys:
- `public.priests` (`id BIGINT`, `name TEXT`, `photo_url TEXT`, `bio TEXT`, `visitation_hours JSONB`, `tenant_id BIGINT`)
- `public.services` (`id BIGINT`, `title_ar TEXT`, `description TEXT`, `schedule JSONB`, `location TEXT`, `tenant_id BIGINT`)
- `public.service_slots` (`id BIGINT`, `service_id BIGINT REFERENCES services(id)`, `starts_at TIMESTAMPTZ`, `ends_at TIMESTAMPTZ`, `capacity INT`, `price INT`, `status TEXT`, `location TEXT`, `tenant_id BIGINT`)
- `public.bookings` (`id BIGINT`, `slot_id BIGINT`, `user_id UUID`, `status public.booking_status`, `paid_amount INT`, `payment_ref TEXT`, `locked_until TIMESTAMPTZ`, `tenant_id BIGINT`)
- `public.payments` (`id BIGINT`, `booking_id BIGINT`, `gateway_ref TEXT`, `amount INT`, `status public.payment_status`, `raw_webhook JSONB`, `tenant_id BIGINT`)
- `public.announcements` (`id BIGINT`, `title_ar TEXT`, `body_ar TEXT`, `target_role public.app_role`, `published_at TIMESTAMPTZ`, `tenant_id BIGINT`)
- `public.faq` (`id BIGINT`, `question_ar TEXT`, `answer_ar TEXT`, `position INT`, `published BOOLEAN`, `tenant_id BIGINT`)
- `public.complaints` (`id BIGINT`, `user_id UUID`, `category TEXT`, `body_encrypted BYTEA`, `status public.complaint_status`, `assigned_to UUID`, `tenant_id BIGINT`)
- `public.videos` (`id BIGINT`, `title_ar TEXT`, `event_date TIMESTAMPTZ`, `yt_url TEXT`, `price INT`, `privacy public.video_privacy`, `expires_after_days INT`, `tenant_id BIGINT`)
- `public.video_purchases` (`id BIGINT`, `video_id BIGINT`, `user_id UUID`, `payment_id BIGINT`, `access_granted_at TIMESTAMPTZ`, `tenant_id BIGINT`)
- `public.event_outbox` (`id BIGINT`, `event_type TEXT`, `payload JSONB`, `status public.outbox_status`, `retry_count INT`, `next_retry_at TIMESTAMPTZ`, `handler_type public.event_handler_type`, `tenant_id BIGINT`)
- `public.whatsapp_outbox` (`id BIGINT`, `phone TEXT`, `template_name TEXT`, `params JSONB`, `status TEXT`, `attempts INT`, `next_attempt_at TIMESTAMPTZ`, `tenant_id BIGINT`)
- `public.refund_requests` (`id BIGINT`, `payment_id BIGINT`, `amount NUMERIC(12,2)`, `status TEXT`, `attempts INT`, `tenant_id BIGINT`)

### 2.3 Portal Views
- `public.v_services` (`security_invoker = true`): Services aggregated with next available slot timestamp and starting price.
- `public.v_priests` (`security_invoker = true`): Clergy directory for portal display.
- `public.v_faq` (`security_invoker = true`): Published FAQ items ordered by position.
- `public.v_schedule_today` (`security_invoker = true`): Daily schedule with slot availability status.
- `public.v_available_slots` (`security_invoker = true`): Slot booking grid with real-time remaining capacity.
- `public.v_my_bookings` (`security_invoker = true`): Parishioner booking list joined with service details.
- `public.v_my_complaints` (`security_invoker = false`): Submitter metadata access view for complaint history.
- `public.v_complaints` (`security_invoker = false`): Admin-only metadata review view for encrypted complaints box.

---

## 3. Backend Plan Summary (Phase 1 Target)

Phase 1 (Church Directory & Community Portal) delivers:
1. Church Profile & Media (history, patron saints, vision, cover photo, location coordinates).
2. Clergy Directory (priests listing, spiritual responsibilities, confession and visitation schedule).
3. Liturgical Schedule (holy masses, vespers, midnight praises, bible studies).
4. Community Announcements (pinned news, youth alerts, liturgical feast dates).
5. FAQ Knowledge Base (answers to frequent questions regarding sacraments and services).
6. Social & External Links (YouTube channel, Facebook page, WhatsApp broadcast group, SoundCloud hymns, map directions).

---

## 4. Divergence & Reconciliation Table

| Area | Backend Draft Spec | Live Repository Implementation | Conflict / Divergence | Reconciliation Decision |
| :--- | :--- | :--- | :--- | :--- |
| **User Profile Table** | `profiles` (UUID PK) | `public.users` (UUID PK linked to `auth.users`) | High | **Strictly keep `public.users`**. Do not create a redundant `profiles` table. All user foreign keys reference `public.users(id)`. |
| **FAQ Table Name** | `faqs` (plural) | `public.faq` (singular) | Medium | **Strictly keep `public.faq`** and view `public.v_faq`. Do not create or rename to `faqs`. |
| **Liturgical Schedule** | `service_schedules` table | `public.services` + `public.service_slots` | High | **Strictly keep `services` & `service_slots`**. Real-time capacity, slot locking, and booking engines depend directly on this model. |
| **Entity Primary Keys** | `UUID` everywhere | `BIGINT generated always as identity` | Critical | **Strictly use `BIGINT`** for all domain entities. Only `users.id` and auth references use `UUID`. |
| **RBAC Roles** | `PARISHIONER`, `PRIEST`, `ADMIN`, `SUPER_ADMIN` | `USER`, `ADMIN` (collapsed in migration 0033) | High | **Strictly use `USER` and `ADMIN`**. Admin policies use `public.is_admin()`. |
| **Social Links** | Proposed feature | Not yet implemented | None | **Implement via migration `0042_social_links.sql`** with `BIGINT` PK and RLS. |
| **Outbox Claim Security** | Publicly invokable in 0039 | Restricted to `service_role` in 0041 | Resolved | Enforce `service_role` only execution for `claim_event_outbox_batch(INT)`. |

---

## 5. Adapted Phase 1 Implementation Contract

### 5.1 New Migration: `0042_social_links.sql`
```sql
-- 0042: social_links table for church directory (Phase 1)
create table public.social_links (
  id bigint generated always as identity primary key,
  platform text not null, -- 'YOUTUBE', 'FACEBOOK', 'WHATSAPP', 'SOUNDCLOUD', 'MAPS', 'WEBSITE'
  title_ar text not null,
  url text not null,
  icon_name text,
  position int not null default 0,
  is_active boolean not null default true,
  tenant_id bigint not null default public.tenant_id(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.social_links enable row level security;

-- Public read for active links
create policy "social_links_public_read" on public.social_links
  for select to anon, authenticated
  using (is_active = true and tenant_id = public.tenant_id());

-- Admin write
create policy "social_links_admin_write" on public.social_links
  for all to authenticated
  using (public.is_admin() and tenant_id = public.tenant_id())
  with check (public.is_admin() and tenant_id = public.tenant_id());

grant select on public.social_links to anon, authenticated;
grant all on public.social_links to authenticated;
```

### 5.2 Flutter Integration Contracts
- **Mobile (`apps/mobile`)**:
  - Direct consumption of `v_services`, `v_priests`, `v_faq`, `announcements`, and `social_links`.
  - Arabic RTL layout first.
  - BLoC/Cubit pattern for new Phase 1 modules.
- **Admin (`apps/admin`)**:
  - CRUD interfaces for `announcements`, `faq`, `priests`, `services`, and `social_links`.
  - Protected by `allowedAdminRoles = {'ADMIN'}` guard.

---

## 6. Out of Scope for Phase 1

1. **Table Renaming**: No table renaming (`faq` -> `faqs`, `services` -> `service_schedules`).
2. **ID Refactoring**: No primary key type migrations (`BIGINT` -> `UUID`).
3. **Role Restoration**: No reintroduction of legacy `PRIEST`, `SUPER_ADMIN`, or `PARISHIONER` enum values.
4. **Booking Seam**: Phase 0 booking/payment intake seam (`reserveAndPay`, `retryCheckout`, `apply_payment`) remains locked and undisturbed.
5. **Video Storage**: No direct video storage uploads (YouTube unlisted OAuth2 model strictly retained).
