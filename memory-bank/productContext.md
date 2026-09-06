# Product Context: Church Digital Platform

## Why This Project Exists
Coptic Orthodox churches in Egypt handle high-volume parishioner interactions: weekly liturgy reservations, sacramental occasions (baptisms, weddings, funerals), seasonal summer camp trips, anonymous complaints, and community services. 
Traditionally handled via ad-hoc phone calls, paper notebooks, and manual cash handoffs, this causes seat overbooking, missed confirmations, financial tracking gaps, and lack of transparency for parishioners.

This digital platform modernizes church operations while respecting traditional administrative oversight (e.g. phone verification calls, priest coordination, cash-in-hand parishioner demographics).

## Two Core Product Pillars

### Pillar 1: Booking & Event Services
1. **Vacations & Trips (مصايف ورحلات)**:
   - Multi-seat / family spot bookings for retreats and summer camps.
   - Dynamic capacity tracking and slot exhaustion broadcast.
2. **Weddings (إكليل وزفاف)**:
   - Ceremony slot reservation, hall allocation, priest coordination.
   - Configurable add-on services (photography, sound system, decoration).
3. **Newborns & Baptisms (المعمودية والمواليد)**:
   - Sacramental baptism time booking, newborn registry data.
4. **Condolences & Funerals (العزاء وصلاة الجناز)**:
   - Hall and church service scheduling for funeral prayers and condolence gatherings.
5. **Liturgies & Masses (القداسات)**:
   - Recurring weekly service slot registration with capacity management.

### Pillar 2: Community & Parish Information
1. **About Us & Clergy (عن الكنيسة والآباء)**:
   - Church history, patron saint details, contact links, priest directory and biographies.
2. **Church Services Schedule (مواعيد القداسات والاجتماعات)**:
   - Structured timetable of vespers, youth meetings, Bible studies, and masses.
3. **Voluntary Work & Servants (التطوع والخدمة)**:
   - Parishioner registration for voluntary service departments (Sunday School, elderly care, logistics, IT).
4. **Encrypted Complaints Inbox (الشكاوى والمقترحات)**:
   - Anonymous/confidential parishioner feedback encrypted via PGP/Vault, readable only by authorized senior clergy/superadmin.

## Key Terminology & Conceptual Model
- **Booking**: A single seat or event reservation. A booking enters `AWAITING_CALL` (قيد التنفيذ) or `SUBMITTED` until an administrator verifies it. Avoid: "Order", "Ticket", "Reservation".
- **Confirmation Call**: The mandatory admin phone verification that moves a booking from `AWAITING_CALL` to `CONFIRMED`.
- **Service Slot**: A scheduled calendar event with defined capacity and pricing (liturgy, trip, baptism).
- **Event Booking**: An appointment-style ceremony booking with resource/venue locking and configurable extra services.
- **Extra Services**: Optional add-ons (photography, chairs, sound system, decorations) with fixed or quantity pricing and snapshot prices at booking time.
- **Refund Request**: An administrative queue item created when payment succeeds on an expired or cancelled booking lock.

## User Experience & Accessibility
- **Arabic-First**: 100% RTL interface, Cairo/Tajawal typography, culturally natural Egyptian Arabic phrasing.
- **Zero Raw English Errors**: All client-facing error payloads adhere strictly to `{"error": CODE, "message_ar": "..."}`.
- **Dual Payment Flexibility**: Full support for Paymob online wallets/cards alongside manual admin cash receipts.
