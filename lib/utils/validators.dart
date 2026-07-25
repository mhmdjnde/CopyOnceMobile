import 'password_policy.dart';

/// Form validation shared by the auth screens.
///
/// These mirror the server's rules so users get instant feedback, but the
/// server remains the authority — never treat a client pass as authorization.
abstract class Validators {
  /// Minimum password length, owned by [PasswordPolicy] so the rule, the
  /// message, and the strength meter can never disagree.
  static int get minPasswordLength => PasswordPolicy.minLength;

  /// Length of the sign-up code Supabase emails.
  ///
  /// Must match the project's "Email OTP Length" setting (Authentication →
  /// Sign In / Providers → Email). Supabase allows 6–10; this project sends 8.
  /// Change one and you must change the other.
  static const int verificationCodeLength = 8;

  static final RegExp _emailPattern = RegExp(
    r'^[\w.!#$%&’*+/=?^`{|}~-]+@[\w-]+(\.[\w-]+)+$',
  );

  static final RegExp _digitsOnly = RegExp(r'^\d+$');

  static String? email(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your email address.';
    if (!_emailPattern.hasMatch(email)) return 'Enter a valid email address.';
    return null;
  }

  /// New-password rules. Pass [email] so a password that merely restates the
  /// address can be rejected.
  static String? password(String? value, {String? email}) =>
      PasswordPolicy.validate(value, email: email);

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

  /// Emailed sign-up code: exactly [verificationCodeLength] digits.
  ///
  /// Catches typos before spending a server attempt; the server still decides
  /// whether the code is genuine.
  static String? verificationCode(String? value) {
    final code = value?.trim() ?? '';
    if (code.isEmpty) return 'Enter the code we emailed you.';
    if (!_digitsOnly.hasMatch(code)) return 'Codes are digits only.';
    if (code.length != verificationCodeLength) {
      return 'The code is $verificationCodeLength digits.';
    }
    return null;
  }

  /// Authenticator apps emit 6 digits — fixed by the TOTP standard, unlike the
  /// emailed code's configurable length.
  static const int authenticatorCodeLength = 6;

  static String? authenticatorCode(String? value) {
    final code = value?.trim() ?? '';
    if (code.isEmpty) return 'Enter the code from your authenticator.';
    if (!_digitsOnly.hasMatch(code)) return 'Codes are digits only.';
    if (code.length != authenticatorCodeLength) {
      return 'The code is $authenticatorCodeLength digits.';
    }
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
