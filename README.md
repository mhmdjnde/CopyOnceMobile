# CopyOnce

A cross-platform clipboard sync app built with Flutter and Supabase.

## Setup

1. Install dependencies:

   ```sh
   flutter pub get
   ```

2. Create your local Supabase config from the template:

   ```sh
   cp env/supabase.example.json env/supabase.json
   ```

   Fill in your project URL and **publishable** key from the Supabase dashboard
   under *Settings → API Keys*. `env/supabase.json` is gitignored — never commit
   real keys, and never put a secret key in this file. It ships in the client.

3. Apply the database schema by running the SQL in `supabase/migrations/`
   through the Supabase SQL Editor, oldest file first.

4. Run the app:

   ```sh
   flutter run --dart-define-from-file=env/supabase.json
   ```

   Launching without the `--dart-define-from-file` flag shows a setup screen
   instead of failing at the first network call.

## Architecture

| Layer | Location | Responsibility |
| --- | --- | --- |
| Presentation | `lib/screens`, `lib/widgets` | Widgets only; no business logic |
| State | `lib/controllers` | `AuthController` (`ChangeNotifier` via `provider`) |
| Data | `lib/repositories` | `AuthRepository` — the only caller of the Supabase SDK |
| Platform | `lib/services` | Secure session storage (Keystore / Keychain) |

`AuthGate` (`lib/navigation/auth_gate.dart`) is the root route and decides
between splash, the signed-out flow, and the app based on session state.

## Auth flow

```
Splash → Onboarding → Sign Up ─┬─→ (session issued) → Main app
                               └─→ (confirm email on) → Check Email → Sign In
                    ↘ Sign In ──→ Main app
                        ↘ Forgot Password → reset email
```

Returning users with a stored session skip straight to the main app.

## Database

`profiles` holds one row per user, created automatically by an
`on_auth_user_created` trigger on `auth.users`. Row Level Security restricts
every user to their own row; there is no client insert or delete policy.

## Commands

```sh
dart format .
flutter analyze
flutter test
flutter build apk --debug --dart-define-from-file=env/supabase.json
```
