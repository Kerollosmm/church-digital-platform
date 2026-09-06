# Play Internal Testing Checklist (before inviting testers)

1. Build a debug AAB: `flutter build appbundle --debug --dart-define=SUPABASE_URL=$STAGING_URL --dart-define=SUPABASE_ANON_KEY=$STAGING_ANON` in apps/mobile.
2. Upload to Play Console → Testing → Internal testing → Create release.
3. Add testers' Google accounts (max 100) → Send invite.
4. Testers install via opt-in link on a physical device (Android 9+).
5. On-device matrix per tester phone (Vodafone/Etisalat/Orange): OTP login, home schedule, service booking, Paymob sandbox checkout, my-bookings status, complaint submission, video purchase (mock).
6. Confirm WhatsApp test-number messages arrive (booking_payment_received, booking_confirmed) — requires staging WHATSAPP_PHONE_ID + test phone opted in.
7. Report failures with logcat: `adb logcat -s flutter` and attach `flutter run --debug` trace.
8. Release criteria: no crashes on 5 consecutive testers; booking→pay flow passes on 3 networks; priest override verified by staff.
