# Egyptian Coptic Orthodox Church Digital Platform — Comprehensive Domain & System Guide

> **Primary Source References:**
> - Master Blueprint: [`docs/superpowers/plans/2026-08-05-church-digital-platform.md`](file:///c:/church/docs/superpowers/plans/2026-08-05-church-digital-platform.md)
> - Conventions & Constraints: [`docs/superpowers/plans/conventions.md`](file:///c:/church/docs/superpowers/plans/conventions.md)
> - Rules & Guardrails: [`AGENTS.md`](file:///c:/church/AGENTS.md) and [`GEMINI.md`](file:///c:/church/GEMINI.md)

---

## 1. Parish Mission & Target Audience

The **Egyptian Coptic Orthodox Church Digital Platform** is a specialized parish management and parishioner service ecosystem tailored to the liturgical, sacramental, and pastoral workflow of Coptic Orthodox churches in Egypt (e.g., Cairo, Alexandria, and regional dioceses).

It replaces fragmented manual scheduling, cash handling, and paper records with a secure, Arabic-first digital platform serving two primary user groups:

### User Personas & Roles (`roles_permissions`):
1. **Parishioners (الشعب) — Mobile App (iOS / Android):**
   - Reserve seats for **Holy Mass / Divine Liturgy** (القداس الإلهي) for individuals and family members.
   - Book private 1-on-1 appointments for the **Sacrament of Confession** (سر الاعتراف) with their Father of Confession (أب الاعتراف).
   - Access **Sacramental Services** (الخدمات والنهضات): Baptism (المعمودية), Matrimony/Crowning (الإكليل), and Unction of the Sick (مسحة المرضى).
   - Purchase access to recorded spiritual lectures, sermons, and annual feast conventions (النهضات الكنسية).
   - Send encrypted, private pastoral complaints/counseling requests directly to priests.
   - Receive official church announcements and WhatsApp/FCM push reminders.
2. **Church Administration & Clergy — Admin Web Dashboard (PWA):**
   - **`PRIEST` (الآباء الكهنة):** View confession schedules, manage pastoral availability, read/decrypt assigned private complaints, and execute Emergency Overrides (إلغاء/تعديل اضطراري).
   - **`ADMIN` (الخدام وإدارة الكنيسة):** Manage service slots, handle manual cash bookings at church office, process refund requests, and review parish analytics.
   - **`SUPER_ADMIN` (إدارة النظام الكنسي):** System configuration, RBAC role assignment, security key management, and audit log inspection.

---

## 2. Church Liturgical & Sacramental Modules

| Module | Spiritual & Pastoral Scope | Technical Implementation |
|---|---|---|
| **Divine Liturgy Booking (حجز القداسات)** | Multi-seat family reservation for Mass services with slot capacity enforcement. Ensures fair distribution of attendance across parishioners. | Transactional row lock (`SELECT FOR UPDATE` on `service_slots`) inside `book_slot()` RPC with 20-min payment reservation lock (`locked_until`). `pg_cron` cancels expired locks every minute. |
| **Confession Appointments (مواعيد الاعتراف)** | Private booking calendar connecting parishioners with their Father of Confession (أب الاعتراف). Maintains priest schedule privacy and prevents double-booking. | Filtered views (`v_priest_slots`), slot assignment per priest, RPC status transitions (`AWAITING_CALL` / `CONFIRMED`). |
| **Encrypted Complaints Box (صندوق الشكاوى الاستشاري)** | Direct, confidential channel for parishioners to send sensitive spiritual, family, or personal complaints to assigned priests without public visibility. | In-database symmetric encryption (`pgp_sym_encrypt`) using Supabase Vault key `COMPLAINTS_KEY`. Decryption restricted to assigned priest via `decrypt_complaint()` RPC. |
| **Recorded Video Sales (النهضات والمؤتمرات)** | Distribution of recorded spiritual lectures and choir recordings during feast seasons (e.g., St. Mary Fasting / Holy Week). | Sold via Paymob. Webhook triggers WhatsApp outbox message containing **unlisted YouTube link**. `youtube-expiry` edge function automatically manages video access duration via OAuth2 bearer tokens (`videos.update`). Zero YouTube API quota consumed during purchase. |
| **Priest Emergency Override (تعديل طوارئ الكاهن)** | Allows priests to cancel/reschedule a liturgy or confession slot in case of urgent pastoral duties (e.g., unexpected funeral or sick visit). | Executed via `emergency_override()` RPC. Reschedules bookings, enqueues refunds into `refund_requests`, and triggers automated Egyptian Arabic WhatsApp apology messages. |

---

## 3. Egyptian Technical & Local Infrastructure Context

- **Localization:** Arabic-first interface with right-to-left (RTL) layout mandatory for all mobile and admin web screens.
- **Egyptian Payment Gateways:** Paymob Accept integration supporting local payment methods:
  - **Vodafone Cash** (فودافون كاش)
  - **Meeza Cards** (ميزة)
  - **Fawry** (فورى)
  - **Bank Cards** (Visa / Mastercard)
  - All currency transactions expressed in **Egyptian Pounds (EGP / جنيه مصري)**.
- **Phone OTP Authentication:** Supabase Auth utilizing Egyptian mobile numbers (+20) via SMS / WhatsApp OTP fallback.
- **WhatsApp Cloud API Outbox:** Transactional notifications delivered via official Meta-approved WhatsApp templates (`booking_confirmed`, `payment_received`, `booking_cancelled`, `otp_auth`) with explicit parishioner opt-in (`whatsapp_optins`).

---

## 4. Monorepo Architecture & Backend Controls

```
C:\church
├── apps/
│   ├── mobile/         [Flutter Mobile - iOS/Android for Parishioners]
│   └── admin/          [Flutter Web PWA for Priests & Admins]
├── supabase/           [Postgres 16 + RLS + RPCs + Edge Functions + pg_cron]
└── docs/               [Master Plan 2026-08-05 & TDD Phase Plans]
```

### Key Architectural Principles:
1. **Supabase Core Stack:** PostgreSQL 16 database, RLS security boundary, PostgREST API, Supabase Auth, Realtime updates, Deno Edge Functions, `pg_cron`.
2. **RPC-Only State Transitions:** Clients cannot perform direct `INSERT`/`UPDATE` operations on business tables. All state changes run through `SECURITY DEFINER` SQL RPCs (`book_slot`, `confirm_booking`, `cancel_booking`, `emergency_override`).
3. **Stale Payment Race Safety:** Paymob webhooks for stale or cancelled bookings set payment status to `REFUND_PENDING` and enqueue a row in `refund_requests`. Seats are never granted on stale payments.
4. **Secrets & Security Isolation:** Third-party API keys (Paymob HMAC, WhatsApp tokens, Google OAuth2 credentials) reside strictly inside Deno Edge Functions and Supabase Vault; never exposed to Flutter client apps.
