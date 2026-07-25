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
      expect(controller.pendingConfirmationEmail, isNull);
    });

    test(
      'returns false and records the email when confirmation is required',
      () async {
        repository.signUpOutcome = SignUpOutcome.confirmationRequired;

        final result = await controller.signUp(
          email: '  new@example.com  ',
          password: 'secret123',
        );

        expect(result, isFalse);
        expect(controller.pendingConfirmationEmail, 'new@example.com');
      },
    );

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
