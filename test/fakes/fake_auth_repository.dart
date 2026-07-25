import 'dart:async';

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

  final List<String> calls = [];
  String? lastEmail;
  String? lastDisplayName;

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
  Future<void> sendPasswordReset(String email) async {
    calls.add('sendPasswordReset');
    lastEmail = email;
    if (failure != null) throw failure!;
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
