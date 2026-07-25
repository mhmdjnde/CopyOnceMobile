import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repositories/auth_repository.dart';

/// Whether the app knows yet if someone is signed in.
enum AuthStatus {
  /// Still restoring a persisted session — show the splash.
  unknown,

  /// Password accepted, but the account has an authenticator that has not been
  /// satisfied yet.
  ///
  /// Supabase issues a genuine session at this point (assurance level 1), so
  /// treating it as signed-in would make two-factor authentication decorative.
  /// The gate keeps such a session out of the app until it steps up to aal2.
  awaitingSecondFactor,

  authenticated,
  unauthenticated,
}

/// Owns authentication state for the whole app.
///
/// Widgets read [status], [isBusy], and [errorMessage] from here and call the
/// action methods; they never touch [AuthRepository] or Supabase directly.
class AuthController extends ChangeNotifier {
  AuthController(this._repository) {
    _status = _resolveStatus(hasSession: _repository.currentUser != null);
    _subscription = _repository.authStateChanges.listen(_onAuthStateChanged);
  }

  final AuthRepository _repository;
  StreamSubscription<AuthState>? _subscription;

  AuthStatus _status = AuthStatus.unknown;
  AuthStatus get status => _status;

  bool _isBusy = false;

  /// True while an auth request is in flight — drives button spinners.
  bool get isBusy => _isBusy;

  String? _errorMessage;

  /// User-safe error from the last action, or null.
  String? get errorMessage => _errorMessage;

  AuthFailureReason? _failureReason;

  /// Why the last action failed, for screens that route on it rather than only
  /// showing [errorMessage]. Null when the last action succeeded.
  AuthFailureReason? get failureReason => _failureReason;

  User? get currentUser => _repository.currentUser;

  /// Email address awaiting its sign-up verification code, or null.
  String? _pendingVerificationEmail;
  String? get pendingVerificationEmail => _pendingVerificationEmail;

  void _onAuthStateChanged(AuthState state) {
    _status = _resolveStatus(hasSession: state.session != null);
    notifyListeners();
  }

  /// A session alone is not enough: an account with an authenticator has to
  /// clear it before the app opens.
  AuthStatus _resolveStatus({required bool hasSession}) {
    if (!hasSession) return AuthStatus.unauthenticated;
    return _repository.needsSecondFactor
        ? AuthStatus.awaitingSecondFactor
        : AuthStatus.authenticated;
  }

  /// Clears any error so a screen does not show a stale message.
  void clearError() {
    if (_errorMessage == null && _failureReason == null) return;
    _errorMessage = null;
    _failureReason = null;
    notifyListeners();
  }

  /// Returns true when the account is signed in, false when a verification code
  /// was emailed instead, and null when the attempt failed.
  ///
  /// On false, [pendingVerificationEmail] holds the address the code went to.
  Future<bool?> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    return _run(() async {
      final outcome = await _repository.signUp(
        email: email,
        password: password,
        displayName: displayName,
      );
      if (outcome == SignUpOutcome.codeSent) {
        _pendingVerificationEmail = email.trim();
        return false;
      }
      _pendingVerificationEmail = null;
      return true;
    });
  }

  /// Verifies the emailed sign-up code and signs the account in.
  ///
  /// Returns true on success — the repository's auth stream then flips
  /// [status] to authenticated — and null on failure.
  Future<bool?> verifySignUpCode(String code) {
    final email = _pendingVerificationEmail;
    if (email == null) {
      _errorMessage = 'Start again from the sign-up screen.';
      notifyListeners();
      return Future.value(null);
    }

    return _run(() async {
      await _repository.verifySignUpCode(email: email, token: code);
      _pendingVerificationEmail = null;
      return true;
    });
  }

  /// Emails a fresh sign-up code to [pendingVerificationEmail], optionally
  /// setting that address first for an account that was never verified.
  ///
  /// Returns true once the code has been sent, null on failure.
  Future<bool?> resendSignUpCode({String? email}) {
    if (email != null) _pendingVerificationEmail = email.trim();
    final target = _pendingVerificationEmail;
    if (target == null) {
      _errorMessage = 'Start again from the sign-up screen.';
      notifyListeners();
      return Future.value(null);
    }

    return _run(() async {
      await _repository.resendSignUpCode(target);
      return true;
    });
  }

  /// Returns true on success, null on failure.
  ///
  /// A failure with [AuthFailureReason.unconfirmedEmail] means the account
  /// exists but never verified its code; the sign-in screen resends one.
  Future<bool?> signIn({required String email, required String password}) {
    return _run(() async {
      await _repository.signIn(email: email, password: password);
      return true;
    });
  }

  /// Returns true once the reset email has been requested, null on failure.
  Future<bool?> sendPasswordReset(String email) {
    return _run(() async {
      await _repository.sendPasswordReset(email);
      return true;
    });
  }

  /// Completes a sign-in that is waiting on an authenticator code.
  ///
  /// Returns true once the session steps up, null on failure. Verifying issues a
  /// new session, so the auth stream moves [status] to authenticated; the status
  /// is recomputed here as well in case the SDK reuses the session object and
  /// emits nothing.
  Future<bool?> verifySecondFactor(String code) {
    return _run(() async {
      await _repository.verifySecondFactor(code);
      _status = _resolveStatus(hasSession: _repository.currentUser != null);
      return true;
    });
  }

  Future<void> signOut() async {
    await _run(() async {
      await _repository.signOut();
      return true;
    });
  }

  /// Runs [action] with busy/error bookkeeping. Returns null if it failed.
  Future<bool?> _run(Future<bool> Function() action) async {
    _isBusy = true;
    _errorMessage = null;
    _failureReason = null;
    notifyListeners();
    try {
      return await action();
    } on AuthFailure catch (failure) {
      _errorMessage = failure.message;
      _failureReason = failure.reason;
      return null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
