import 'package:flutter/foundation.dart';

import '../models/two_factor.dart';
import '../repositories/auth_repository.dart';

/// Owns the account-security screens: password changes and the authenticator.
///
/// Separate from `AuthController`, which owns session state for the whole app.
/// This one is created for the security screens and disposed with them, so
/// enrollment secrets do not outlive the flow that needs them.
class SecurityController extends ChangeNotifier {
  SecurityController(this._repository);

  final AuthRepository _repository;

  bool _isBusy = false;
  bool get isBusy => _isBusy;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  AuthFailureReason? _failureReason;
  AuthFailureReason? get failureReason => _failureReason;

  TwoFactorStatus? _twoFactorStatus;

  /// Null until [loadTwoFactorStatus] has answered — screens show a loading
  /// state rather than guessing "off".
  TwoFactorStatus? get twoFactorStatus => _twoFactorStatus;

  TotpEnrollment? _enrollment;

  /// The in-progress enrollment, held only while the setup screen is open.
  TotpEnrollment? get enrollment => _enrollment;

  void clearError() {
    if (_errorMessage == null && _failureReason == null) return;
    _errorMessage = null;
    _failureReason = null;
    notifyListeners();
  }

  /// Forgets enrollment secrets as soon as setup ends, successfully or not.
  void discardEnrollment() {
    if (_enrollment == null) return;
    _enrollment = null;
    notifyListeners();
  }

  Future<void> loadTwoFactorStatus() async {
    await _run(() async {
      _twoFactorStatus = await _repository.twoFactorStatus();
      return true;
    });
  }

  /// Returns true on success, null on failure.
  Future<bool?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    return _run(() async {
      await _repository.updatePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      return true;
    });
  }

  /// Begins authenticator setup, exposing the secret through [enrollment].
  Future<bool?> startTwoFactorSetup() {
    return _run(() async {
      _enrollment = await _repository.startTwoFactorEnrollment();
      return true;
    });
  }

  /// Confirms setup with a code from the authenticator app.
  Future<bool?> confirmTwoFactorSetup(String code) {
    final enrollment = _enrollment;
    if (enrollment == null) {
      _errorMessage = 'Start the setup again.';
      notifyListeners();
      return Future.value(null);
    }

    return _run(() async {
      await _repository.confirmTwoFactor(
        factorId: enrollment.factorId,
        code: code,
      );
      _enrollment = null;
      _twoFactorStatus = await _repository.twoFactorStatus();
      return true;
    });
  }

  /// Removes the authenticator, which requires a current code.
  Future<bool?> disableTwoFactor(String code) {
    final factorId = _twoFactorStatus?.factorId;
    if (factorId == null) {
      _errorMessage = 'No authenticator is set up on this account.';
      notifyListeners();
      return Future.value(null);
    }

    return _run(() async {
      await _repository.disableTwoFactor(factorId: factorId, code: code);
      _twoFactorStatus = const TwoFactorStatus.disabled();
      return true;
    });
  }

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
}
