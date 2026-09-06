# Phase 0: Technical Research & Architectural Decisions

### 1. State Management: Riverpod Notifier vs. Bloc
- **Decision**: Riverpod 3.x with code generation (`riverpod_generator`) using `Notifier` and `AsyncNotifier`.
- **Rationale**: Built-in compile-time safety, auto-dispose capabilities for cached views, seamless async state handling without boilerplate, and superior testability via container overrides.

### 2. Offline Pass Caching Strategy for Low-Connectivity Sanctuaries
- **Decision**: SQLite via `drift` / `hive` caching for validated reservation passes + local QR generation + fallback 4-character entry code.
- **Rationale**: Sanctuaries often have thick limestone walls and subterranean chapels with zero cellular connectivity; parishioners must be able to present valid passes offline.

### 3. Admin Multi-Factor 3-Step Authentication State Machine
- **Decision**: Phone/Password (Step 1) -> SMS OTP (Step 2) -> Dedicated 6-digit Priest/Admin PIN (Step 3) with AES-256 salt & Supabase RPC validation (`verify_admin_pin`). Self-service OTP PIN recovery path supported.
- **Rationale**: Protects sacrosanct parishioner confession schedules and liturgical override capabilities against stolen session tokens.
