import 'dart:async';

import 'package:copy_once/models/two_factor.dart';
import 'package:copy_once/repositories/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// In-memory [AuthRepository] stand-in.
///
/// Uses `implements` rather than `extends` so no Supabase client is required.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.signedInUser});

  final _controller = StreamController<AuthState>.broadcast();

  User? signedInUser;

  /// When set, the next call throws this instead of succeeding.
  AuthFailure? failure;

  /// Outcome returned by [signUp] when it succeeds.
  SignUpOutcome signUpOutcome = SignUpOutcome.signedIn;

  /// Drives [needsSecondFactor], so tests can simulate an account with an
  /// authenticator attached.
  @override
  bool needsSecondFactor = false;

  /// Status returned by [twoFactorStatus].
  TwoFactorStatus twoFactorState = const TwoFactorStatus.disabled();

  /// Enrollment returned by [startTwoFactorEnrollment].
  TotpEnrollment enrollmentToReturn = const TotpEnrollment(
    factorId: 'factor-1',
    secret: 'JBSWY3DPEHPK3PXP',
    otpauthUri:
        'otpauth://totp/CopyOnce:user@example.com?secret=JBSWY3DPEHPK3PXP',
  );

  final List<String> calls = [];
  String? lastEmail;
  String? lastDisplayName;
  String? lastCode;

  @override
  Stream<AuthState> get authStateChanges => _controller.stream;

  @override
  User? get currentUser => signedInUser;

  @override
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    calls.add('signUp');
    lastEmail = email;
    lastDisplayName = displayName;
    if (failure != null) throw failure!;
    return signUpOutcome;
  }

  @override
  Future<void> verifySignUpCode({
    required String email,
    required String token,
  }) async {
    calls.add('verifySignUpCode');
    lastEmail = email;
    lastCode = token;
    if (failure != null) throw failure!;
  }

  @override
  Future<void> resendSignUpCode(String email) async {
    calls.add('resendSignUpCode');
    lastEmail = email;
    if (failure != null) throw failure!;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    calls.add('signIn');
    lastEmail = email;
    if (failure != null) throw failure!;
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    if (failure != null) throw failure!;
    signedInUser = null;
  }

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    calls.add('updatePassword');
    if (failure != null) throw failure!;
  }

  @override
  Future<TwoFactorStatus> twoFactorStatus() async {
    calls.add('twoFactorStatus');
    if (failure != null) throw failure!;
    return twoFactorState;
  }

  @override
  Future<TotpEnrollment> startTwoFactorEnrollment() async {
    calls.add('startTwoFactorEnrollment');
    if (failure != null) throw failure!;
    return enrollmentToReturn;
  }

  @override
  Future<void> confirmTwoFactor({
    required String factorId,
    required String code,
  }) async {
    calls.add('confirmTwoFactor');
    lastCode = code;
    if (failure != null) throw failure!;
    twoFactorState = TwoFactorStatus(isEnabled: true, factorId: factorId);
  }

  @override
  Future<void> disableTwoFactor({
    required String factorId,
    required String code,
  }) async {
    calls.add('disableTwoFactor');
    lastCode = code;
    if (failure != null) throw failure!;
    twoFactorState = const TwoFactorStatus.disabled();
  }

  @override
  Future<void> verifySecondFactor(String code) async {
    calls.add('verifySecondFactor');
    lastCode = code;
    if (failure != null) throw failure!;
    needsSecondFactor = false;
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    calls.add('sendPasswordReset');
    lastEmail = email;
    if (failure != null) throw failure!;
  }

  /// Pushes a signed-in [AuthState] so tests can drive the controller's
  /// reaction to the auth stream.
  ///
  /// Awaits delivery — a broadcast stream hands the event to listeners in a
  /// microtask, so a synchronous check would read the old status.
  Future<void> emitSignedIn() async {
    _controller.add(
      AuthState(
        AuthChangeEvent.signedIn,
        Session(
          accessToken: 'test-access-token',
          tokenType: 'bearer',
          user: signedInUser ?? fakeUser(),
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> emitSignedOut() async {
    _controller.add(AuthState(AuthChangeEvent.signedOut, null));
    await Future<void>.delayed(Duration.zero);
  }

  void dispose() => _controller.close();
}

/// Minimal [User] for tests that only need a non-null current user.
User fakeUser({String email = 'user@example.com', String? displayName}) {
  return User(
    id: 'test-user-id',
    appMetadata: const {},
    userMetadata: displayName == null ? {} : {'display_name': displayName},
    aud: 'authenticated',
    email: email,
    createdAt: DateTime.utc(2026).toIso8601String(),
  );
}
