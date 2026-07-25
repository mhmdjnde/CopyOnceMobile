import 'package:copy_once/controllers/auth_controller.dart';
import 'package:copy_once/repositories/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_auth_repository.dart';

void main() {
  late FakeAuthRepository repository;
  late AuthController controller;

  setUp(() {
    repository = FakeAuthRepository();
    controller = AuthController(repository);
  });

  tearDown(() {
    controller.dispose();
    repository.dispose();
  });

  group('initial status', () {
    test('is unauthenticated when there is no persisted user', () {
      expect(controller.status, AuthStatus.unauthenticated);
    });

    test('is authenticated when a session was restored', () {
      final restored = FakeAuthRepository(signedInUser: fakeUser());
      final restoredController = AuthController(restored);
      addTearDown(restoredController.dispose);
      addTearDown(restored.dispose);

      expect(restoredController.status, AuthStatus.authenticated);
    });
  });

  group('second factor', () {
    test('a restored session with an authenticator waits for a code', () {
      final pending = FakeAuthRepository(signedInUser: fakeUser())
        ..needsSecondFactor = true;
      final pendingController = AuthController(pending);
      addTearDown(pendingController.dispose);
      addTearDown(pending.dispose);

      // The session is real but only assurance level 1 — treating this as
      // authenticated would let anyone with the password into the app.
      expect(pendingController.status, AuthStatus.awaitingSecondFactor);
    });

    test('signing in with an authenticator does not reach the app', () async {
      repository.needsSecondFactor = true;

      await controller.signIn(
        email: 'user@example.com',
        password: 'Str0ngPassphrase',
      );
      await repository.emitSignedIn();

      expect(controller.status, AuthStatus.awaitingSecondFactor);
    });

    test('verifying the code opens the app', () async {
      repository.needsSecondFactor = true;
      repository.signedInUser = fakeUser();
      await repository.emitSignedIn();
      expect(controller.status, AuthStatus.awaitingSecondFactor);

      final result = await controller.verifySecondFactor('123456');

      expect(result, isTrue);
      expect(controller.status, AuthStatus.authenticated);
      expect(repository.calls, ['verifySecondFactor']);
    });

    test('a rejected code leaves the session waiting', () async {
      repository.needsSecondFactor = true;
      repository.signedInUser = fakeUser();
      await repository.emitSignedIn();
      repository.failure = const AuthFailure(
        'That code did not match.',
        reason: AuthFailureReason.invalidTotpCode,
      );

      final result = await controller.verifySecondFactor('000000');

      expect(result, isNull);
      expect(controller.status, AuthStatus.awaitingSecondFactor);
      expect(controller.failureReason, AuthFailureReason.invalidTotpCode);
    });

    test('no authenticator means a session goes straight in', () async {
      repository.signedInUser = fakeUser();
      await repository.emitSignedIn();

      expect(controller.status, AuthStatus.authenticated);
    });
  });

  group('signIn', () {
    test('returns true and leaves no error on success', () async {
      final result = await controller.signIn(
        email: 'user@example.com',
        password: 'secret123',
      );

      expect(result, isTrue);
      expect(controller.errorMessage, isNull);
      expect(repository.calls, ['signIn']);
    });

    test('returns null and exposes the failure message on error', () async {
      repository.failure = const AuthFailure('Incorrect email or password.');

      final result = await controller.signIn(
        email: 'user@example.com',
        password: 'wrong',
      );

      expect(result, isNull);
      expect(controller.errorMessage, 'Incorrect email or password.');
    });

    test('clears isBusy after a failure', () async {
      repository.failure = const AuthFailure('Incorrect email or password.');

      await controller.signIn(email: 'user@example.com', password: 'wrong');

      expect(controller.isBusy, isFalse);
    });

    test('is busy while the request is in flight', () async {
      final future = controller.signIn(
        email: 'user@example.com',
        password: 'secret123',
      );

      expect(controller.isBusy, isTrue);
      await future;
      expect(controller.isBusy, isFalse);
    });
  });

  group('signUp', () {
    test('returns true when a session is issued immediately', () async {
      repository.signUpOutcome = SignUpOutcome.signedIn;

      final result = await controller.signUp(
        email: 'new@example.com',
        password: 'secret123',
      );

      expect(result, isTrue);
      expect(controller.pendingVerificationEmail, isNull);
    });

    test('returns false and records the email when a code was sent', () async {
      repository.signUpOutcome = SignUpOutcome.codeSent;

      final result = await controller.signUp(
        email: '  new@example.com  ',
        password: 'secret123',
      );

      expect(result, isFalse);
      expect(controller.pendingVerificationEmail, 'new@example.com');
    });

    test('passes the display name through to the repository', () async {
      await controller.signUp(
        email: 'new@example.com',
        password: 'secret123',
        displayName: 'Sam',
      );

      expect(repository.lastDisplayName, 'Sam');
    });

    test('returns null on failure', () async {
      repository.failure = const AuthFailure(
        'An account with that email already exists.',
      );

      final result = await controller.signUp(
        email: 'taken@example.com',
        password: 'secret123',
      );

      expect(result, isNull);
      expect(
        controller.errorMessage,
        'An account with that email already exists.',
      );
    });
  });

  group('verifySignUpCode', () {
    /// Puts the controller in the state the verify screen runs in: signed up,
    /// waiting on a code.
    Future<void> signUpAwaitingCode() async {
      repository.signUpOutcome = SignUpOutcome.codeSent;
      await controller.signUp(email: 'new@example.com', password: 'secret123');
      repository.calls.clear();
    }

    test('sends the pending email and the code to the repository', () async {
      await signUpAwaitingCode();

      final result = await controller.verifySignUpCode('12345678');

      expect(result, isTrue);
      expect(repository.calls, ['verifySignUpCode']);
      expect(repository.lastEmail, 'new@example.com');
      expect(repository.lastCode, '12345678');
    });

    test('clears the pending email once verified', () async {
      await signUpAwaitingCode();

      await controller.verifySignUpCode('12345678');

      expect(controller.pendingVerificationEmail, isNull);
    });

    test('reports a rejected code with its reason', () async {
      await signUpAwaitingCode();
      repository.failure = const AuthFailure(
        'That code is incorrect or has expired. Request a new one.',
        reason: AuthFailureReason.invalidCode,
      );

      final result = await controller.verifySignUpCode('000000');

      expect(result, isNull);
      expect(controller.failureReason, AuthFailureReason.invalidCode);
      // Still pending, so the user can try another code.
      expect(controller.pendingVerificationEmail, 'new@example.com');
    });

    test(
      'fails without calling the repository when nothing is pending',
      () async {
        final result = await controller.verifySignUpCode('12345678');

        expect(result, isNull);
        expect(repository.calls, isEmpty);
        expect(controller.errorMessage, isNotNull);
      },
    );
  });

  group('resendSignUpCode', () {
    test('uses the pending email when none is given', () async {
      repository.signUpOutcome = SignUpOutcome.codeSent;
      await controller.signUp(email: 'new@example.com', password: 'secret123');

      final result = await controller.resendSignUpCode();

      expect(result, isTrue);
      expect(repository.calls, ['signUp', 'resendSignUpCode']);
      expect(repository.lastEmail, 'new@example.com');
    });

    test('adopts an explicit email, for an unverified sign-in', () async {
      final result = await controller.resendSignUpCode(
        email: '  stale@example.com  ',
      );

      expect(result, isTrue);
      expect(controller.pendingVerificationEmail, 'stale@example.com');
      expect(repository.lastEmail, 'stale@example.com');
    });

    test(
      'fails without calling the repository when nothing is pending',
      () async {
        final result = await controller.resendSignUpCode();

        expect(result, isNull);
        expect(repository.calls, isEmpty);
      },
    );
  });

  group('failureReason', () {
    test('surfaces the reason the repository reported', () async {
      repository.failure = const AuthFailure(
        'Your email address is not verified yet.',
        reason: AuthFailureReason.unconfirmedEmail,
      );

      await controller.signIn(email: 'user@example.com', password: 'secret123');

      expect(controller.failureReason, AuthFailureReason.unconfirmedEmail);
    });

    test('is cleared by the next successful action', () async {
      repository.failure = const AuthFailure(
        'Your email address is not verified yet.',
        reason: AuthFailureReason.unconfirmedEmail,
      );
      await controller.signIn(email: 'user@example.com', password: 'secret123');

      repository.failure = null;
      await controller.signIn(email: 'user@example.com', password: 'secret123');

      expect(controller.failureReason, isNull);
    });
  });

  group('clearError', () {
    test('removes a previous error message', () async {
      repository.failure = const AuthFailure('Incorrect email or password.');
      await controller.signIn(email: 'user@example.com', password: 'wrong');
      expect(controller.errorMessage, isNotNull);

      controller.clearError();

      expect(controller.errorMessage, isNull);
    });

    test('does not notify when there is no error', () {
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.clearError();

      expect(notifications, 0);
    });
  });

  test('a new action clears the previous error', () async {
    repository.failure = const AuthFailure('Incorrect email or password.');
    await controller.signIn(email: 'user@example.com', password: 'wrong');
    expect(controller.errorMessage, isNotNull);

    repository.failure = null;
    await controller.signIn(email: 'user@example.com', password: 'secret123');

    expect(controller.errorMessage, isNull);
  });

  test('signOut delegates to the repository', () async {
    await controller.signOut();
    expect(repository.calls, ['signOut']);
  });
}
