# ADR 0001: Domain Model Refinements & 7-Module Architecture

- **Status**: superseded by master plan scope review (2026-08-09)
- **Date**: 2026-08-09

> **Superseded note:** A later scope review re-included **Paid Video Access (M3)** and the **Encrypted Complaints Box (X0)** as core platform features — see master blueprint `2026-08-05-church-digital-platform.md` decisions A1-A11. The 7-module architecture and all other decisions below stand; only the Exclusion clause (§4) is overridden for those two items. CMeeting replacement (Households, Visitation, QR Attendance, Drift Sync) remains excluded.

## Context

Scope review finalized the platform boundaries into exactly two pillars: **Booking Services** (4 modules) and **Community & Parish Info** (3 modules). Non-aligned features (Paid Videos, Encrypted Complaints, CMeeting Household/Visitation tracking) are excluded.

## Decisions

1. **7-Module System Architecture**:
   - **Pillar 1: Booking Services**
     1. Vacations & Trips (مصايف ورحلات)
     2. Weddings (إكليل وزفاف)
     3. New Borns & Baptisms (المعمودية والمواليد)
     4. Condolences & Funerals (العزاء وصلاة الجناز)
   - **Pillar 2: Community & Parish Info**
     5. About Us & Church (عن الكنيسة والآباء)
     6. Church Services & Masses (القداسات والاجتماعات)
     7. Voluntary & Servant Work (التطوع والخدمة)

2. **Booking Seats (`seat_count = 1`)**: Standardized on 1 booking = 1 seat default. Multi-seat purchases create separate booking transactions to maintain atomic `SELECT FOR UPDATE` capacity locking.
3. **Paymob Refunds (Manual Admin Queue)**: `refund_requests` acts as a manual operational queue for church administrators. Automated Paymob Refund API calls are excluded.
4. **Exclusions**:
   - Paid Video Access (M3 / YouTube sales) → **EXCLUDED**
   - Encrypted Complaints Box → **EXCLUDED**
   - CMeeting Replacement (Households, Visitation, QR Attendance, Drift Sync) → **EXCLUDED**

## Consequences

- Database schema & Flutter UI modules scoped strictly to the 7 defined components.
- Service slots table and UI filters categorized by exact event types: `VACATION`, `WEDDING`, `BAPTISM`, `CONDOLENCE`, `MASS`.
- Voluntary work module added for parishioner service sign-up requests.
