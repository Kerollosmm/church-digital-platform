# Coptic Church Platform — Mobile User Application

The cross-platform mobile client application for the Coptic Church Digital Platform, built with **Flutter**.

## 📱 Features

- **Mass & Event Booking**: Search liturgy schedules, reserve multi-seat slots, and receive instant QR tickets.
- **Payment Processing**: Integrated online checkout supporting card payments and Egyptian mobile wallets (Vodafone Cash / Paymob).
- **Coptic Calendar & Announcements**: View upcoming church feasts, meetings, and unlisted event broadcasts.
- **Arabic / RTL UI**: Native Right-To-Left layout and localized Arabic text for church members.

## 📁 Repository Structure

```
.
├── android/              # Native Android project configuration
├── ios/                  # Native iOS project configuration
├── lib/
│   ├── app_router.dart   # GoRouter navigation configuration
│   ├── main.dart         # Flutter app entry point
│   ├── core/             # Auth gateways, Supabase clients, themes, networks
│   ├── features/         # Feature modules (auth, mass booking, payments)
│   └── screens/          # Top-level screen views
├── test/                 # Flutter widget & unit test suite
└── pubspec.yaml          # Flutter dependencies & assets config
```

## 🛠️ Tech Stack & Key Packages

- **Framework**: Flutter (Dart SDK `^3.12.0`)
- **Navigation**: `go_router` (`^17.4.0`)
- **State Management**: `flutter_riverpod` (`^3.4.2`)
- **Backend Integration**: `supabase_flutter` (`^2.17.1`)
- **Localization**: `flutter_localizations` (RTL Arabic support)

## 🚀 Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.12.0 or higher)
- Android Studio / Xcode (for device emulators)

### Setup & Local Execution

1. **Install Dependencies**:
   ```bash
   flutter pub get
   ```

2. **Run Application**:
   ```bash
   flutter run --dart-define=SUPABASE_URL=http://localhost:54321 --dart-define=SUPABASE_ANON_KEY=<your-anon-key>
   ```

3. **Execute Unit & Widget Tests**:
   ```bash
   flutter test
   ```
