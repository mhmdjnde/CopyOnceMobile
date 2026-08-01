import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/two_factor.dart';

/// Result of a sign-up attempt.
enum SignUpOutcome {
  /// A session was returned — the user is signed in and can enter the app.
  signedIn,

  /// The project requires email confirmation, so Supabase emailed a
  /// verification code instead of issuing a session.
  codeSent,
}

/// What went wrong, for the few cases a screen needs to react to rather than
/// just display.
///
/// Keeps message parsing inside [AuthRepository]: no screen should ever match
/// on server error text.
enum AuthFailureReason {
  /// The account exists but its email was never verified, so the sign-up code
  /// is still outstanding.
  unconfirmedEmail,

  /// The submitted verification code was wrong or has expired. Supabase does
  /// not reliably distinguish the two, so neither does this.
  invalidCode,

  /// The current password given while changing passwords was wrong.
  wrongPassword,

  /// Sign-up was attempted with an address that already has an account.
  emailTaken,

  /// The authenticator code did not match. Usually a stale code or a clock
  /// that has drifted.
  invalidTotpCode,

  /// Anything else — show [AuthFailure.message] and nothing more.
  other,
}

/// Thrown for any auth failure, carrying a message safe to show to the user.
///
/// Never carries tokens, passwords, or raw server payloads.
class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.reason = AuthFailureReason.other});

  final String message;
  final AuthFailureReason reason;

  @override
  String toString() => 'AuthFailure: $message';
}

/// The only place in the app that talks to Supabase Auth directly.
///
/// Translates SDK exceptions into [AuthFailure] with user-safe messages so no
/// screen ever handles a raw [AuthException].
class AuthRepository {
  AuthRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  /// Emits on sign-in, sign-out, and token refresh.
  Stream<AuthState> get authStateChanges => _auth.onAuthStateChange;

  /// The signed-in user, or null.
  User? get currentUser => _auth.currentUser;

  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
    String? displayName,
  }) {
    return _guard(() async {
      final response = await _auth.signUp(
        email: email.trim(),
        password: password,
        data: displayName == null || displayName.trim().isEmpty
            ? null
            : {'display_name': displayName.trim()},
      );
      // With email confirmation on, Supabase does not error when the address is
      // already taken — it returns a hollow user so an attacker cannot use
      // sign-up to discover who has an account. The giveaway is an empty
      // identities list, and without this check the screen would cheerfully ask
      // for a code that was never sent.
      final identities = response.user?.identities;
      if (response.session == null &&
          identities != null &&
          identities.isEmpty) {
        throw const AuthFailure(
          'An account with that email already exists. Sign in instead.',
          reason: AuthFailureReason.emailTaken,
        );
      }

      return response.session == null
          ? SignUpOutcome.codeSent
          : SignUpOutcome.signedIn;
    });
  }

  /// Exchanges the emailed sign-up code for a session.
  ///
  /// On success Supabase marks the email confirmed and emits a signed-in
  /// [AuthState], which is what moves the app past the auth gate.
  ///
  /// [token] is a one-time credential: it is passed straight through and never
  /// stored or logged.
  Future<void> verifySignUpCode({
    required String email,
    required String token,
  }) {
    return _guard(
      () => _auth.verifyOTP(
        email: email.trim(),
        token: token.trim(),
        type: OtpType.signup,
      ),
    );
  }

  /// Emails a fresh sign-up code, invalidating the previous one.
  Future<void> resendSignUpCode(String email) {
    return _guard(
      () => _auth.resend(email: email.trim(), type: OtpType.signup),
    );
  }

  Future<void> signIn({required String email, required String password}) {
    return _guard(
      () => _auth.signInWithPassword(email: email.trim(), password: password),
    );
  }

  Future<void> signOut() => _guard(() => _auth.signOut());

  // ── Password ───────────────────────────────────────────────────────────────

  /// Changes the password after proving the current one.
  ///
  /// Supabase lets a live session set a new password without re-entering the
  /// old one, which means a borrowed unlocked phone is enough to lock the owner
  /// out. Re-authenticating first closes that hole. The check reuses the
  /// current email, so a signed-out caller cannot get here.
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    return _guard(() async {
      final email = _auth.currentUser?.email;
      if (email == null) {
        throw const AuthFailure('Sign in again to change your password.');
      }

      try {
        await _auth.signInWithPassword(email: email, password: currentPassword);
      } on AuthException {
        // Reported as a wrong current password rather than a generic failure,
        // and deliberately not distinguished from other sign-in errors.
        throw const AuthFailure(
          'That is not your current password.',
          reason: AuthFailureReason.wrongPassword,
        );
      }

      if (currentPassword == newPassword) {
        throw const AuthFailure(
          'Choose a password you have not used here before.',
        );
      }

      await _auth.updateUser(UserAttributes(password: newPassword));
    });
  }

  // ── Two-factor (TOTP) ──────────────────────────────────────────────────────

  /// Whether a verified authenticator is attached to this account.
  Future<TwoFactorStatus> twoFactorStatus() {
    return _guard(() async {
      final factors = await _auth.mfa.listFactors();
      final verified = _verifiedTotp(factors.totp);

      if (verified == null) return const TwoFactorStatus.disabled();
      return TwoFactorStatus(
        isEnabled: true,
        factorId: verified.id,
        enrolledAt: verified.createdAt,
      );
    });
  }

  /// Creates an unverified TOTP factor and returns what the user needs to add
  /// it to an authenticator app.
  ///
  /// Nothing is protected until [confirmTwoFactor] succeeds, so abandoning this
  /// screen leaves the account exactly as it was — apart from a stale
  /// unverified factor, which [startTwoFactorEnrollment] clears on the next
  /// attempt.
  Future<TotpEnrollment> startTwoFactorEnrollment() {
    return _guard(() async {
      await _removeUnverifiedFactors();

      final response = await _auth.mfa.enroll(
        factorType: FactorType.totp,
        issuer: 'CopyOnce',
        friendlyName: 'CopyOnce ${DateTime.now().toIso8601String()}',
      );

      final totp = response.totp;
      if (totp == null) {
        throw const AuthFailure('Could not start setup. Please try again.');
      }

      return TotpEnrollment(
        factorId: response.id,
        secret: totp.secret,
        otpauthUri: totp.uri,
      );
    });
  }

  /// Proves the authenticator is in sync, turning the factor on.
  Future<void> confirmTwoFactor({
    required String factorId,
    required String code,
  }) {
    return _guard(
      () => _auth.mfa.challengeAndVerify(factorId: factorId, code: code.trim()),
    );
  }

  /// Turns the factor off, requiring a current code so a borrowed session
  /// cannot quietly weaken the account.
  Future<void> disableTwoFactor({
    required String factorId,
    required String code,
  }) {
    return _guard(() async {
      await _auth.mfa.challengeAndVerify(factorId: factorId, code: code.trim());
      await _auth.mfa.unenroll(factorId);
    });
  }

  /// True when the current session is password-only but the account has a
  /// verified factor — the point at which sign-in must step up.
  bool get needsSecondFactor {
    final level = _auth.mfa.getAuthenticatorAssuranceLevel();
    return level.currentLevel == AuthenticatorAssuranceLevels.aal1 &&
        level.nextLevel == AuthenticatorAssuranceLevels.aal2;
  }

  /// Completes a stepped-up sign-in with a code from the authenticator.
  Future<void> verifySecondFactor(String code) {
    return _guard(() async {
      final factors = await _auth.mfa.listFactors();
      final verified = _verifiedTotp(factors.totp);

      if (verified == null) {
        throw const AuthFailure('No authenticator is set up on this account.');
      }

      await _auth.mfa.challengeAndVerify(
        factorId: verified.id,
        code: code.trim(),
      );
    });
  }

  /// The account's active authenticator, or null. Written out rather than using
  /// `package:collection` for one call.
  Factor? _verifiedTotp(List<Factor> totpFactors) {
    for (final factor in totpFactors) {
      if (factor.status == FactorStatus.verified) return factor;
    }
    return null;
  }

  /// Drops half-finished factors so repeated setup attempts cannot pile up and
  /// hit the enrolled-factor limit.
  Future<void> _removeUnverifiedFactors() async {
    final factors = await _auth.mfa.listFactors();
    for (final factor in factors.all) {
      if (factor.status == FactorStatus.unverified) {
        await _auth.mfa.unenroll(factor.id);
      }
    }
  }

  Future<void> sendPasswordReset(String email) {
    return _guard(() => _auth.resetPasswordForEmail(email.trim()));
  }

  /// Runs [action], converting SDK and network errors into [AuthFailure].
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthFailure {
      // Already translated — an [action] that raised this deliberately must not
      // be re-reported as a connection problem by the catch-all below.
      rethrow;
    } on AuthException catch (e) {
      throw _failureFor(e);
    } on Exception {
      // Deliberately does not include the raw error: it can contain request
      // details we do not want surfaced in the UI.
      throw const AuthFailure(
        'Could not reach CopyOnce. Check your connection and try again.',
      );
    }
  }

  /// Maps a Supabase error onto a user-safe message and, where a screen needs
  /// to act on it, an [AuthFailureReason].
  ///
  /// Prefers `e.code` — the documented, stable identifier — and falls back to
  /// message matching for deployments that do not send one.
  AuthFailure _failureFor(AuthException e) {
    final code = e.code;
    final message = e.message.toLowerCase();

    if (code == 'email_not_confirmed' || message.contains('not confirmed')) {
      return const AuthFailure(
        'Your email address is not verified yet.',
        reason: AuthFailureReason.unconfirmedEmail,
      );
    }
    if (code == 'mfa_verification_failed' ||
        code == 'mfa_verification_rejected') {
      return const AuthFailure(
        'That code did not match. Check your authenticator and try the current '
        'code.',
        reason: AuthFailureReason.invalidTotpCode,
      );
    }
    if (code == 'mfa_challenge_expired') {
      return const AuthFailure(
        'That code expired before it reached us. Enter the current one.',
        reason: AuthFailureReason.invalidTotpCode,
      );
    }
    if (code == 'too_many_enrolled_mfa_factors') {
      return const AuthFailure(
        'This account already has an authenticator. Remove it before adding '
        'another.',
      );
    }
    if (code == 'mfa_totp_enroll_not_enabled' ||
        code == 'mfa_totp_verify_not_enabled') {
      return const AuthFailure(
        'Two-factor authentication is not enabled for this project yet.',
      );
    }
    if (code == 'otp_expired' ||
        message.contains('token has expired') ||
        message.contains('invalid token') ||
        message.contains('otp')) {
      return const AuthFailure(
        'That code is incorrect or has expired. Request a new one.',
        reason: AuthFailureReason.invalidCode,
      );
    }
    if (code == 'invalid_credentials' ||
        message.contains('invalid login credentials')) {
      return const AuthFailure('Incorrect email or password.');
    }
    if (code == 'user_already_exists' ||
        message.contains('already registered') ||
        message.contains('already been registered')) {
      return const AuthFailure('An account with that email already exists.');
    }
    if (code == 'weak_password' || message.contains('password')) {
      return const AuthFailure('Password must be at least 8 characters.');
    }
    if (code == 'over_email_send_rate_limit' ||
        code == 'over_request_rate_limit' ||
        message.contains('rate limit') ||
        message.contains('too many requests')) {
      return const AuthFailure(
        'Too many attempts. Wait a moment and try again.',
      );
    }
    return const AuthFailure('Something went wrong. Please try again.');
  }
}
