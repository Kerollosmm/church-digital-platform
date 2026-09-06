# External Onboarding Checklist (master plan §7 — START NOW, runs parallel to all coding)

Weekly review ritual (every Sunday, 15 min, dev standup): update Status per row;
escalate anything older than its lead time to the church liaison owner.

| # | Dependency | Action needed | Lead time | Owner | Status (date) |
|---|-----------|---------------|-----------|-------|---------------|
| 1 | Paymob merchant account | Retired per ADR 0003 (single-rail manual payment verification) | — | — | RETIRED (2026-08-23) |
| 2 | Meta Business Manager + WhatsApp Business Account | Business verification, phone, test number | 2-7 days | Dev | NOT_STARTED |
| 3 | WhatsApp template submissions | booking_confirmed, booking_payment_received ({{1}}=link), cancelled, rescheduled, apology, otp (+ Phase 1: booking_offer) | 3-14 days/round | Dev | NOT_STARTED |
| 4 | YouTube channel phone verification | One-time; needed for >15 min uploads | minutes-hours | Media team | NOT_STARTED |
| 5 | Google Play Console ($25) | Account setup | 1-5 days | Dev | NOT_STARTED |
| 6 | Supabase project | Sign up, org + project, region Frankfurt | 1 day | Dev | NOT_STARTED |
| 7 | SMS provider for OTP | Twilio trial/paid or Egyptian aggregator (webhook custom provider) | 1-3 days | Dev | NOT_STARTED |
| 8 | Domain + DNS | e.g. church-name-eg.org | 1 day | Church admin | NOT_STARTED |

Status values: NOT_STARTED / IN_PROGRESS / DONE / BLOCKED / RETIRED.

Open questions to resolve alongside (master §16): (1) which church committee member owns onboarding follow-ups; (2) Twilio vs local SMS aggregator — test on Vodafone/Etisalat/Orange.
