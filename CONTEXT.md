# Church Digital Platform

Digital platform (Flutter Mobile + Flutter Web Admin) structured into two main pillars: Booking Services and Community & Parish Info.

## System Tree

### Booking Services
1. **Vacations & Trips (مصايف ورحلات)**: Multi-seat/spot bookings for church retreats, trips, and summer camps.
2. **Weddings (إكليل وزفاف)**: Ceremony slot reservation and priest/hall coordination.
3. **New Borns & Baptisms (المعمودية والمواليد)**: Baptism service booking and newborn registration.
4. **Condolences & Funerals (العزاء وصلاة الجناز)**: Hall/service booking for funeral prayers and condolence gatherings.

### Community & Parish Info
5. **About Us & Church (عن الكنيسة والآباء)**: Church history, contact details, location, and priests directory.
6. **Church Services & Masses (القداسات والاجتماعات)**: Weekly mass schedules, vespers, and meeting timetables.
7. **Voluntary & Servant Work (التطوع والخدمة)**: Servant registration, voluntary service areas, and sign-up requests.

## Language

**Booking**:
A single seat/spot reservation for a parishioner in a service slot. A booking waits in `AWAITING_CALL` (قيد التنفيذ) until an admin confirms it by phone — like order processing.
_Avoid_: Order, ticket, reservation

**Confirmation Call**:
The mandatory admin phone call that moves a Booking from `AWAITING_CALL` to `CONFIRMED`. The booking phone number is collected at booking time exactly for this call.
_Avoid_: Verification, approval (for the call itself)

**Video Deliverable**:
A personal unlisted YouTube video for a Booking holder (baptism/wedding filming add-on), linked to the buyer by exact phone-number match and delivered automatically via WhatsApp. Carries a title only.
_Avoid_: Video sale, catalog entry, captioned video

**Global Video**:
A public catalog video — external YouTube link (opens on YouTube, never embedded), free or paid per video (paid via Paymob).
_Avoid_: Embedded player, personal video

**Service Slot**:
A scheduled calendar event with defined capacity and pricing (Vacation/مصيف, Wedding/إكليل, Baptism/معمودية, Condolence/عزاء, Mass/قداس).
_Avoid_: Mass time, event instance

**Voluntary Work**:
Opportunities and sign-up requests for parishioners to serve and participate in church voluntary services (التطوع والخدمة).
_Avoid_: Job, paid work, recruitment

**Refund Request**:
An administrative queue entry created when a payment webhook arrives for an expired/cancelled booking.
_Avoid_: Auto-refund, chargeback
