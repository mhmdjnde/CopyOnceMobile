/// Supabase connection settings.
///
/// Values are injected at build time and are never hardcoded in source:
///
/// ```sh
/// flutter run --dart-define-from-file=env/supabase.json
/// ```
///
/// `env/supabase.json` is gitignored. Copy `env/supabase.example.json` and fill
/// it in to set up a new machine.
abstract class SupabaseConfig {
  static const String url = String.fromEnvironment('SUPABASE_URL');

  /// The publishable (anon) key. Safe to ship in a client *only* because every
  /// table enforces Row Level Security — never place a secret key here.
  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  /// True when both values were supplied at build time.
  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;

  /// Guidance shown when the app is launched without the dart-defines.
  static const String missingConfigMessage =
      'Supabase is not configured.\n\n'
      'Run the app with:\n'
      'flutter run --dart-define-from-file=env/supabase.json';
}
