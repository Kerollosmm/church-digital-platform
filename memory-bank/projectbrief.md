# Project Brief: Church Digital Platform

## Project Overview
Monorepo digital platform for a single Egyptian Coptic Orthodox Church (`C:\church`).
Provides an integrated digital experience across mobile parishioners and church administrators with localized Egyptian payment gateways and messaging infrastructure.

## Core Objectives
1. **Booking & Event Services**: Enable parishioners to reserve church services (retreats/trips, wedding ceremonies, baptisms, funerals/condolences, liturgies/masses) with configurable extra services and administrative review.
2. **Community & Parish Portal**: Provide church announcements, priest directory, mass schedules, voluntary service recruitment, and encrypted parishioner complaints.
3. **Operational Administration**: Enable church staff and priests to manage service slots, manually book reservations, review and confirm submissions, record cash and online payments, manage content, and audit operations.

## Target Platforms & Architecture
- **Parishioner Mobile App**: Flutter Mobile (Android/iOS) using Riverpod, GoRouter, Arabic-first RTL design.
- **Admin Web Dashboard**: Flutter Web PWA using Riverpod, GoRouter, `fl_chart`, Arabic-first RTL dashboard.
- **Backend**: Supabase (PostgreSQL 16, Row Level Security, PostgREST APIs, Deno Edge Functions, `pg_cron` schedulers, Realtime Broadcast).
- **Integrations**:
  - **Paymob**: Egyptian payment gateway (Visa/Mastercard, Mobile Wallets) in EGP (integer piastres).
  - **Meta Cloud API (WhatsApp)**: Outbox event-driven transactional messaging for OTPs, booking confirmations, receipts, and rejections.
  - **Firebase Cloud Messaging (FCM v1)**: Push notifications.

## Key Project Boundaries & Invariants
- **Single-Church Deployment**: Tenant scaffolding (`tenant_id = 1`) remains internal; no multi-tenant complexity exposed to users.
- **RPC-Only Write Seam**: Financial and sensitive mutations (`payments`, `complaints`, `roles_permissions`, `audit_log`) are forbidden from direct client DML; executed exclusively through hardened `SECURITY DEFINER` RPCs.
- **Pivot Decided (2026-08-17)**: Paid personal filmed-video feature cancelled and decommissioned; replaced by **Event Booking Extra Services** (Specs 007 & 008).
- **Currency Standard**: All monetary figures stored and computed in **piastres** (integer cents, 1 EGP = 100).
- **Order-Processing Booking Model**: Bookings enter `AWAITING_CALL` / `SUBMITTED` until confirmed by church administration.
