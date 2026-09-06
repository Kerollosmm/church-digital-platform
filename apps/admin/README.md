# Coptic Church Platform — Admin Web Portal

The administrative web portal for church priests and system administrators, built with **Flutter Web**.

## 💻 Features

- **Slot & Capacity Management**: Schedule Masses, set seat limits, lock/unlock booking windows.
- **Booking Management**: Manual booking (cash), emergency override (reschedule + apology + refund), refund queue.
- **Financial Management**: Manual payment proof review (approve/reject), direct cash collection, and payout channel configuration.
- **Analytics Dashboard**: Slot utilization, payment/refund trends, and booking volume charts with CSV export.
- **Role-Based Navigation**: View restrictions powered by Supabase Auth RLS claims (`ADMIN`, `SUPER_ADMIN`).

## 📁 Repository Structure

```
.
├── lib/
│   ├── app_router.dart   # GoRouter web routing
│   ├── main.dart         # Flutter Web entry point
│   ├── core/             # Auth gateways, Supabase clients & web layout
│   ├── features/         # Auth, slot scheduling, booking management, analytics
│   └── screens/          # Web dashboard views
├── web/                  # HTML templates, favicons & manifest.json
├── test/                 # Web unit & widget tests
└── pubspec.yaml          # Flutter dependencies & web config
```

## 🛠️ Tech Stack & Key Packages

- **Framework**: Flutter Web (Dart SDK `^3.12.0`)
- **Navigation**: `go_router` (`^17.4.0`)
- **State Management**: `flutter_riverpod` (`^3.4.2`)
- **Backend Integration**: `supabase_flutter` (`^2.17.1`)

## 🚀 Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.12.0 or higher)
- Google Chrome (or modern browser for Flutter Web debugging)

### Setup & Local Execution

1. **Install Dependencies**:
   ```bash
   flutter pub get
   ```

2. **Run Web App Locally**:
   ```bash
   flutter run -d chrome --dart-define=SUPABASE_URL=http://localhost:54321 --dart-define=SUPABASE_ANON_KEY=<your-anon-key>
   ```

3. **Execute Tests**:
   ```bash
   flutter test
   ```

4. **Build Production Web Bundle**:
   ```bash
   flutter build web
   ```
