# Mobile Design System — Implementation Plan

**Date:** 2026-08-09 · **Scope:** `apps/mobile` (Flutter) only — **user screens only**; admin dashboard screens (booking_monitor, emergency_override, encrypted_inbox, secure_complaints, analytics_reports, finance_refunds) are deferred to the future `apps/admin` (Flutter Web) plan.
**Design references (authoritative — copy tokens/colors/strings character-for-character, never from memory):**
- `docs/design/DESIGN.md` — tokens (colors, typography, radii, spacing) + brand rules
- `docs/design/<screen>/code.html` — layout spec per screen (`home_hub`, `phone_otp_authentication`, `service_booking`, `digital_ticket`, `media_store`, `secure_checkout`); `screen.png` is the visual reference

**Architecture contract (unchanged):** UI → controllers → repository interface → Supabase impl; no `supabase_flutter` imports in screens/controllers; Arabic UI strings only in `services/app_strings.dart`; no client-side lock math; all existing data sources (PortalRepository, BookingRepository, `db.rpc`) keep working — screens are presentation only.

**Workflow:** test-first per task (failing test → implement → run → PASS → commit `(mobile) feat: <summary>`). Continue this plan before the GoRouter/DI tasks of `2026-08-09-mobile-architecture-fixes.md` (the 5-tab shell below is the ShellRoute skeleton for Task 4 there).

---

## Design tokens (from DESIGN.md — exact values)

**Style:** Modern Glassmorphism + Minimalism. RTL by default, icons precede text, right-aligned.

| Role | Value | Flutter use |
|---|---|---|
| primary | `#000000` | headers, primary actions (Material `primary`) |
| primary-container | `#131b2e` | deep navy surfaces (OTP screen bg) |
| on-primary-container | `#7c839b` | muted light-blue text on navy |
| secondary | `#904d00` | gold/bronze accents, CTAs (Material `secondary`) |
| secondary-container | `#fe932c` | gold fill (active tab pill, ادفع الآن) |
| on-secondary-container | `#663500` | text on gold |
| surface / background | `#f7f9fb` | app canvas (`scaffoldBackgroundColor`) |
| surface-container-lowest | `#ffffff` | cards |
| surface-container-low | `#f2f4f6` | secondary containers, input bg |
| surface-container | `#eceef0` | greyed containers (booked slots) |
| surface-container-high | `#e6e8ea` | icon circles |
| surface-variant | `#e0e3e5` | chips, dividers, avatar bg |
| on-surface | `#191c1e` | primary text |
| on-surface-variant | `#45464d` | secondary text |
| outline | `#76777d` | borders/ghost button text |
| outline-variant | `#c6c6cd` | card borders |
| error / on-error / error-container / on-error-container | `#ba1a1a` / `#ffffff` / `#ffdad6` / `#93000a` | errors, cancel, CLOSED slots |
| available green | `#166534` (on `#f0fdf4`) | AVAILABLE chip — from service_booking.html |
| booked grey | `#475569` (on `#f8fafc`) | BOOKED chip — from service_booking.html |
| closed red | `#991b1b` (on `#fef2f2`) | CLOSED chip — from service_booking.html |

**Typography:** family **Cairo** (bundled assets `assets/fonts/Cairo-{400,600,700}.ttf` — already downloaded). display-lg 48/60 w700; headline-lg 32/40 w700; headline-lg-mobile 28/36 w700; headline-md 24/32 w600; body-lg 18/28 w400; body-md 16/24 w400; label-md 14/20 w600 (letterSpacing 0.01em).

**Radii:** base 8 (buttons, inputs, chips), cards 16 (`rounded-xl`), pills `9999` (avatars, active tab).

**Spacing (multiples of 4):** xs 8, sm 16, md 24, lg 40, xl 64; page gutter 16 (mobile) / 80 (desktop).

**Glass (level 3):** white 80% + blur 12 + 1px border `#E2E8F0` (top bars, bottom nav, checkout sheet). Card shadow: `0px 4px 20px rgba(15,23,42,0.05)`. Buttons min-height **48**.

---

## Screen map (HTML → Flutter)

| # | HTML screen | Flutter deliverable | Replaces |
|---|---|---|---|
| 2 | `home_hub` | Shell: `TopBar` + `BottomNavScaffold` (5 tabs: الرئيسية / الحجز / الفيديوهات / الشكاوى / حسابي, active = gold pill); Home hub: announcements carousel + quick actions grid + featured meditation | `screens/home_screen.dart` + `features/portal/home_screen.dart` merge into one hub |
| 3 | `phone_otp_authentication` | `LoginScreen` / `OtpScreen` redesign (deep navy bg, glass card, +20 EG phone field, 6-box OTP, gold CTAs) | existing auth screens |
| 4 | `service_booking` | `ServicesListScreen` → `SlotGridScreen` (calendar card + event details + slot cards w/ status chips) → `BookingDetailScreen` (checkout bottom sheet: gold countdown banner + summary + تأكيد الحجز) | existing booking screens |
| 5 | `digital_ticket` | NEW `BookingTicketScreen` (success header, navy-header ticket card w/ dashed rows + QR placeholder, إلغاء real via `cancel_booking`, تعديل → re-enter booking flow, WhatsApp button **omitted** — no backing RPC) | — |
| 6 | `media_store` | `VideoPurchaseScreen` redesign (featured player card + video card grid) | existing |
| 7 | `secure_checkout` | `PaymentRedirectScreen` redesign (payment-method cards + order summary + ادفع الآن → still launches Paymob URL via `launchUrl`; selection UI informational only) | existing |

---

## Task List

| # | Deliverable | Commit |
|---|---|---|
| 1 | Theme: Cairo assets in pubspec + `lib/theme/` (colors, typography, radii, spacing, glass widgets) + `ThemeData` wired in `main.dart` | `(mobile) feat: coptic glassmorphism theme` |
| 2 | App shell: `TopBar` (glass) + `BottomNavScaffold` 5 tabs (gold active pill) + home hub rebuild | `(mobile) feat: home hub + bottom nav shell` |
| 3 | Auth rebuild (phone +20 EG → 6-box OTP, navy glass) | `(mobile) feat: navy glass auth screens` |
| 4 | Booking flow rebuild (calendar card, event details, slot cards AVAILABLE/BOOKED/CLOSED, checkout bottom sheet) | `(mobile) feat: booking flow redesign` |
| 5 | Digital ticket `BookingTicketScreen` (ticket card + QR placeholder + إلغاء via repo) | `(mobile) feat: digital ticket screen` |
| 6 | Media store rebuild (featured player + video grid) | `(mobile) feat: media store redesign` |
| 7 | Checkout redesign (methods + summary + ادفع الآن) | `(mobile) feat: checkout redesign` |
| 8 | Verification checklist + cleanup | — |

---

## Data-backed-only rule (critical)

Every screen renders **only** fields that exist in the DB view/table. Copy column names from the actual definitions in `supabase/migrations/` (0002 bookings, 0008 `v_available_slots`/`v_schedule_today`, announcements, videos). Do NOT invent columns (no `remaining`, no `category`, no `duration`, no `priest_name`, no `church_name`, no `ticket_number`). When a design element has no data backing (priest avatars, QR value, WhatsApp button, filter chips, countdown timer, video thumbnails), either omit it or render a neutral placeholder from `AppStrings` — never a fabricated value, never a stub function. The countdown banner in `service_booking.html` is suppressed (no client-side lock math — architecture decision; show static text `AppStrings.completeBookingPrompt` instead).

## Cross-task constraints

- All new Arabic strings → `services/app_strings.dart`; screens never hardcode.
- Colors/fonts/radii only from `lib/theme/`; no hex literals in screen files.
- Tests use fakes from `test/helpers/` (FakeBookingRepository, TestApp, PortalRepository with FakeSupabase) — never network.
- `test/widget_test.dart` (home smoke with mocked supabase client) must be kept green or migrated to fakes in the same commit.
- Keep existing controllers/repositories untouched unless a signature must change (then update tests in the same commit).

---

## Verification checklist

- `flutter analyze` 0 issues; `flutter test test/` all PASS offline (apps/mobile)
- Greps zero in `lib/`: hex color literals (`#[0-9A-Fa-f]{6}`) outside `lib/theme/`; `Cairo` outside `lib/theme/` + pubspec
- No `supabase_flutter` imports in screens/controllers
- Every new screen has a fake-backed widget test (renders Arabic title + key element; booking ticket test asserts cancel calls repository)
- Manual smoke (when local stack up): login (navy glass) → home hub tabs → book (slot cards + checkout sheet) → ticket → pay stub → `في انتظار الدفع` chip on ticket

## Risks / notes

- `test/widget_test.dart` currently pokes a mocked SupabaseClient through `HomeScreen(supabase:)`; the hub rebuild replaces that screen — migrate the test to `PortalRepository` + FakeSupabase in Task 2's commit.
- `SlotGridScreen` currently keys off `s['slot_status']` — keep that contract; chip color maps AVAILABLE→green, BOOKED→grey, CLOSED→red.
- `payment_redirect_screen` navigation (`/payment-redirect` pushNamed w/ booking id or `{'video': true, ...}`) stays until GoRouter lands; do not break callers (`booking_detail_screen`, `my_bookings_screen`, `video_purchase_screen`).
- Admin screens in the zip are deliberately excluded; note any accidental inclusion in review.
