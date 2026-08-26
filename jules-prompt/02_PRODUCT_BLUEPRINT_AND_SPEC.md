# PRODUCT BLUEPRINT & FUNCTIONAL SPECIFICATION: CHURCH DIGITAL PLATFORM

════════════════════════════════════════════════════════════════════════════════
PURPOSE & PRODUCT VISION
════════════════════════════════════════════════════════════════════════════════
The **Church Digital Platform** is an all-in-one digital operating system for a single Egyptian Coptic Orthodox Church.
It bridges the gap between digital convenience and traditional administrative oversight:
1. **Eliminates Overbooking & Scheduling Conflicts**: Replaces paper logbooks and manual phone notes with atomic slot reservations and database-enforced venue exclusion constraints.
2. **Harmonizes Mixed Egyptian Payment Methods**: Integrates Paymob (Cards + Mobile Wallets) alongside audited in-person cash receipts, all tracked in integer piastres (`1 EGP = 100 piastres`).
3. **Respects Church Pastoral Workflows**: Enforces mandatory review and telephone confirmation steps before ceremonies and bookings are finalized.
4. **Protects Parishioner Privacy**: Provides end-to-end PGCrypto-encrypted feedback and pastoral complaints desks accessible only to authorized clergy.

---

════════════════════════════════════════════════════════════════════════════════
ACTOR PERSONAS & CORE OBJECTIVES
════════════════════════════════════════════════════════════════════════════════

### 1. The Parishioner (Mobile App User)
- **Goal**: Quickly view church schedules, reserve seats for liturgies and trips, request sacramental ceremony dates (Weddings, Baptisms, Funerals) with tailored add-on services, pay online or in cash, and securely submit private pastoral inquiries.
- **Tone & Language**: 100% Arabic-first (Egyptian Coptic phrasing), warm, accessible, RTL, zero English tech jargon.

### 2. Church Administrator / Servant (Web Admin User)
- **Goal**: Review incoming event requests, verify parishioner eligibility via phone, allocate altar/hall resources without schedule overlap, record cash payments, manually book slots for walk-in elderly members, and trigger resends for failed WhatsApp messages.

### 3. Priest / Super Admin (SuperAdmin Portal)
- **Goal**: Decrypt private complaints using administrative keys, manage church service templates, configure event base prices and extra services catalog, oversee financial audit ledgers, and manage servant RBAC permissions.

---

════════════════════════════════════════════════════════════════════════════════
DETAILED FUNCTIONAL FLOWS: HOW THE APP WORKS
════════════════════════════════════════════════════════════════════════════════

### FLOW 1: Sacramental & Trip Slot Booking (Recurring Capacity Model)
1. **Discovery**: Parishioner browses scheduled Liturgies (قداسات), Summer Trips (رحلات ومصايف), or Youth Events.
2. **Realtime Availability**: Live view indicates `AVAILABLE` (متاح), `BOOKED` (محجوز بالكامل), or `CLOSED` (مغلق).
3. **Atomic Reservation**: Parishioner selects seats $\rightarrow$ triggers `book_slot(slot_id, opt_in, user_id)` RPC.
   - Database acquires row lock with `SELECT ... FOR UPDATE` on `service_slots` and counts active bookings against `capacity`.
   - If full $\rightarrow$ aborts atomically and broadcasts `SLOT_EXHAUSTED` over Supabase Realtime.
   - If free $\rightarrow$ creates booking in `PENDING_PAYMENT` (or `AWAITING_CALL` if free of charge).
4. **Payment & Phone Verification**:
   - For paid trips, parishioner pays via Paymob (Cards / Vodafone Cash).
   - Once paid, booking transitions to `AWAITING_CALL` (قيد التنفيذ).
   - Church servant calls parishioner to confirm details $\rightarrow$ servant clicks "Confirm" in Admin Portal $\rightarrow$ advances to `CONFIRMED` $\rightarrow$ triggers WhatsApp confirmation ticket.

---

### FLOW 2: Event Booking with Extra Services (Review-First Model)
1. **Event Selection**: Parishioner chooses an event type:
   - Wedding / Crowning (إكليل وزفاف)
   - Engagement (خطوبة)
   - Baptism (معمودية)
   - Funeral & Condolence (صلاة جناز وقاعة عزاء)
2. **Add-on Services Selection (Extras)**:
   - Parishioner selects optional extra services with live price tally:
     - Fixed services (e.g. Photography / توثيق تصوير: 500 EGP)
     - Quantity services (e.g. Extra Chairs / كراسي إضافية: 10 EGP $\times$ 50 = 500 EGP)
     - Church Choir / خورس الشمامسة, Sound & Lighting / الصوتيات والإضاءة, Altar Flowers / ديكور الكنيسة
3. **Submission**: Parishioner selects requested date/time and submits $\rightarrow$ creates booking in `SUBMITTED` state.
   - Database snapshots unit and total prices in integer piastres into `booking_extra_services`.
   - Outbox enqueues `EVENT_SUBMISSION_RECEIVED` WhatsApp notification to parishioner.
4. **Administrative Review & Scheduling**:
   - Event appears in Admin "Review Queue".
   - Admin verifies schedule, assigns an available Hall/Altar from `venues_resources`.
   - **Exclusion Lock**: PostgreSQL `btree_gist` constraint validates that `(resource_id, tstzrange)` has no collision.
   - Admin clicks **Confirm** $\rightarrow$ status becomes `PENDING_PAYMENT` $\rightarrow$ WhatsApp sends confirmed details + Paymob payment link.
   - (Or Admin clicks **Reject** with mandatory reason $\rightarrow$ status becomes `REJECTED` $\rightarrow$ WhatsApp sends explanation).
5. **Payment (Dual Method)**:
   - **Online**: Parishioner pays online via Paymob $\rightarrow$ Webhook verifies HMAC $\rightarrow$ marks `PAID`.
   - **Cash**: Parishioner visits church office $\rightarrow$ Admin opens `RecordCashPaymentModal`, inputs cash received $\rightarrow$ logs immutable entry in `payment_audit_logs` $\rightarrow$ marks `PAID` / `PARTIALLY_PAID` $\rightarrow$ WhatsApp delivers cash receipt.

---

### FLOW 3: Encrypted Complaints & Pastoral Care Desk
1. **Submission**: Parishioner submits sensitive pastoral question or anonymous complaint in mobile app.
2. **In-DB Encryption**: `submit_complaint_secure` RPC encrypts payload using PGCrypto / Vault public key before writing to disk.
3. **Restricted Decryption**:
   - Regular staff and unprivileged roles CANNOT read raw text.
   - Authorized Priest / SuperAdmin logs into Admin portal with 2FA Admin PIN $\rightarrow$ invokes `decrypt_complaint(id)` RPC to decrypt and review privately.

---

### FLOW 4: Parish Hub & Information Directory
1. **Clergy Directory (الآباء الكهنة)**: Biographies, ordination dates, pastoral contact channels.
2. **Timetable (مواعيد الخدمات)**: Structured schedule of Masses, Vespers (عشيات), Bible studies, and Sunday School meetings.
3. **Announcements & News (أخبار وإعلانات الكنيسة)**: Realtime updates, feast announcements, and pastoral letters.
4. **Volunteering Desk (خدمتي في كنيستي)**: Servants apply for volunteer ministries (Sunday School, IT, Logistics, Scouts).

---

════════════════════════════════════════════════════════════════════════════════
SYSTEM GOALS & QUALITY CRITERIA
════════════════════════════════════════════════════════════════════════════════
1. **Zero Double-Bookings**: Guaranteed at PostgreSQL engine level via `btree_gist` exclusion constraints.
2. **Zero Financial Discrepancies**: 100% of money stored as integer piastres (`1 EGP = 100`). All payment status changes executed via audited `SECURITY DEFINER` RPCs.
3. **Resilient Offline / Background Messaging**: All notifications dispatched via Outbox queues (`whatsapp_outbox`, `event_outbox`) with automatic retry and stuck event reaping.
4. **Zero Untranslated English Errors**: All client responses strictly conform to `{"error": CODE, "message_ar": "..."}`.
5. **100% Automated Test Coverage**: Every database RPC, Edge Function, and Flutter screen verified with reproducible passing test suites.
