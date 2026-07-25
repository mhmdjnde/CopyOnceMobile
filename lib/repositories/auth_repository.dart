import 'package:supabase_flutter/supabase_flutter.dart';

/// Result of a sign-up attempt.
enum SignUpOutcome {
  /// A session was returned — the user is signed in and can enter the app.
  signedIn,

  /// The project requires email confirmation before a session is issued.
  confirmationRequired,
}

/// Thrown for any auth failure, carrying a message safe to show to the user.
///
/// Never carries tokens, passwords, or raw server payloads.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

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
      return response.session == null
          ? SignUpOutcome.confirmationRequired
          : SignUpOutcome.signedIn;
    });
  }

  Future<void> signIn({required String email, required String password}) {
    return _guard(
      () => _auth.signInWithPassword(email: email.trim(), password: password),
    );
  }

  Future<void> signOut() => _guard(() => _auth.signOut());

  Future<void> sendPasswordReset(String email) {
    return _guard(() => _auth.resetPasswordForEmail(email.trim()));
  }

  /// Runs [action], converting SDK and network errors into [AuthFailure].
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthException catch (e) {
      throw AuthFailure(_friendlyMessage(e));
    } on Exception {
      // Deliberately does not include the raw error: it can contain request
      // details we do not want surfaced in the UI.
      throw const AuthFailure(
        'Could not reach CopyOnce. Check your connection and try again.',
      );
    }
  }

  String _friendlyMessage(AuthException e) {
    final message = e.message.toLowerCase();
    if (message.contains('invalid login credentials')) {
      return 'Incorrect email or password.';
    }
    if (message.contains('email not confirmed')) {
      return 'Confirm your email address before signing in.';
    }
    if (message.contains('already registered') ||
        message.contains('already been registered')) {
      return 'An account with that email already exists.';
    }
    if (message.contains('password')) {
      return 'Password must be at least 8 characters.';
    }
    if (message.contains('rate limit') ||
        message.contains('too many requests')) {
      return 'Too many attempts. Wait a moment and try again.';
    }
    return 'Something went wrong. Please try again.';
  }
}
