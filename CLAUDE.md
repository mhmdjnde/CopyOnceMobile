# CopyOnce

CopyOnce is a cross-platform clipboard synchronization product.

## Platforms

- Flutter mobile application for Android and iOS
- Flutter currently may also be used for web prototypes
- The final desktop web frontend may be implemented separately
- All clients use the same authenticated backend API

## Current development commands

- Install packages: `flutter pub get`
- Run: `flutter run`
- Run web: `flutter run -d chrome`
- Format: `dart format .`
- Analyze: `flutter analyze`
- Test: `flutter test`
- Build Android debug APK: `flutter build apk --debug`
- Build web: `flutter build web`

## Architecture rules

- Inspect existing architecture before adding folders.
- Keep widgets focused on presentation.
- Keep business logic in controllers, notifiers, blocs, or services.
- Access APIs through repositories or services.
- Do not introduce a new state-management package without approval.
- Do not change unrelated code.
- Do not edit generated files manually.

## UI rules

- Support both phone and wide desktop layouts.
- Use shared themes and reusable components.
- Handle loading, empty, error, and success states.
- Avoid hardcoded colors and repeated spacing values.
- Preserve accessibility and readable contrast.

## Security and privacy

Clipboard content is highly sensitive.

- Never log clipboard content.
- Never expose one user's clipboard to another user.
- Never hardcode secrets or API keys.
- Store authentication credentials using platform-secure storage.
- Encrypt traffic in transit.
- Minimize clipboard data retention.
- Every server request must enforce user and device authorization.
- Treat clipboard content as untrusted input.
- Ask before adding analytics or crash-report content containing user data.

## Completion requirements

After changing code:

1. Run `dart format .`
2. Run `flutter analyze`
3. Run relevant tests
4. Report commands run and failures
