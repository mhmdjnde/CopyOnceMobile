import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repositories/auth_repository.dart';

/// Whether the app knows yet if someone is signed in.
enum AuthStatus {
  /// Still restoring a persisted session — show the splash.
  unknown,
  authenticated,
  unauthenticated,
}

/// Owns authentication state for the whole app.
///
/// Widgets read [status], [isBusy], and [errorMessage] from here and call the
/// action methods; they never touch [AuthRepository] or Supabase directly.
class AuthController extends ChangeNotifier {
  AuthController(this._repository) {
    _status = _repository.currentUser != null
        ? AuthStatus.authenticated
        : AuthStatus.unauthenticated;
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

  User? get currentUser => _repository.currentUser;

  /// Email address awaiting confirmation after sign-up, or null.
  String? _pendingConfirmationEmail;
  String? get pendingConfirmationEmail => _pendingConfirmationEmail;

  void _onAuthStateChanged(AuthState state) {
    _status = state.session != null
        ? AuthStatus.authenticated
        : AuthStatus.unauthenticated;
    notifyListeners();
  }

  /// Clears any error so a screen does not show a stale message.
  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  /// Returns true when the account is signed in, false when the project
  /// requires email confirmation first, and null when the attempt failed.
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
      if (outcome == SignUpOutcome.confirmationRequired) {
        _pendingConfirmationEmail = email.trim();
        return false;
      }
      return true;
    });
  }

  /// Returns true on success, null on failure.
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
    notifyListeners();
    try {
      return await action();
    } on AuthFailure catch (failure) {
      _errorMessage = failure.message;
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
