import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists the Supabase session in platform-secure storage
/// (Android Keystore / iOS Keychain) rather than plain shared preferences.
///
/// On web, `flutter_secure_storage` offers no OS-backed keystore, so the
/// caller falls back to Supabase's default storage there.
class SecureAuthStorage extends LocalStorage {
  SecureAuthStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _sessionKey = 'copyonce.auth.session';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: _sessionKey);

  @override
  Future<String?> accessToken() => _storage.read(key: _sessionKey);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _sessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _sessionKey, value: persistSessionString);
}

/// Secure storage for the PKCE code verifier used during auth redirects.
class SecurePkceStorage extends GotrueAsyncStorage {
  SecurePkceStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> getItem({required String key}) => _storage.read(key: key);

  @override
  Future<void> removeItem({required String key}) => _storage.delete(key: key);

  @override
  Future<void> setItem({required String key, required String value}) =>
      _storage.write(key: key, value: value);
}

/// Auth storage options for the current platform.
///
/// Returns `null` on web so Supabase uses its own browser-storage defaults.
FlutterAuthClientOptions buildAuthOptions() {
  if (kIsWeb) return const FlutterAuthClientOptions();
  return FlutterAuthClientOptions(
    localStorage: SecureAuthStorage(),
    pkceAsyncStorage: SecurePkceStorage(),
  );
}
