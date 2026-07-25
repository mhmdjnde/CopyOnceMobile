/// Form validation shared by the auth screens.
///
/// These mirror the server's rules so users get instant feedback, but the
/// server remains the authority — never treat a client pass as authorization.
abstract class Validators {
  /// Supabase's minimum. Kept in one place so the rule and its message agree.
  static const int minPasswordLength = 8;

  static final RegExp _emailPattern = RegExp(
    r'^[\w.!#$%&’*+/=?^`{|}~-]+@[\w-]+(\.[\w-]+)+$',
  );

  static String? email(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your email address.';
    if (!_emailPattern.hasMatch(email)) return 'Enter a valid email address.';
    return null;
  }

  static String? password(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Enter a password.';
    if (password.length < minPasswordLength) {
      return 'Use at least $minPasswordLength characters.';
    }
    return null;
  }

  /// Password field on the sign-in screen: presence only, so an old shorter
  /// password still reaches the server instead of being blocked locally.
  static String? requiredPassword(String? value) {
    if ((value ?? '').isEmpty) return 'Enter your password.';
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if ((value ?? '').isEmpty) return 'Re-enter your password.';
    if (value != original) return 'Passwords do not match.';
    return null;
  }

  /// Display name is optional; only length is constrained when provided.
  static String? displayName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return null;
    if (name.length > 50) return 'Keep it under 50 characters.';
    return null;
  }
}
