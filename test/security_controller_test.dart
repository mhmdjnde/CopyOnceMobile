import 'package:copy_once/controllers/security_controller.dart';
import 'package:copy_once/models/two_factor.dart';
import 'package:copy_once/repositories/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_auth_repository.dart';

void main() {
  late FakeAuthRepository repository;
  late SecurityController controller;

  setUp(() {
    repository = FakeAuthRepository();
    controller = SecurityController(repository);
  });

  tearDown(() {
    controller.dispose();
    repository.dispose();
  });

  group('two-factor status', () {
    test('is null until loaded, so screens can show a loading state', () {
      expect(controller.twoFactorStatus, isNull);
    });

    test('reflects an enabled authenticator', () async {
      repository.twoFactorState = const TwoFactorStatus(
        isEnabled: true,
        factorId: 'factor-1',
      );

      await controller.loadTwoFactorStatus();

      expect(controller.twoFactorStatus?.isEnabled, isTrue);
    });
  });

  group('enrollment', () {
    test('exposes the enrollment so the QR can be drawn', () async {
      await controller.startTwoFactorSetup();

      expect(controller.enrollment?.factorId, 'factor-1');
      expect(repository.calls, ['startTwoFactorEnrollment']);
    });

    test('confirming turns 2FA on and drops the secret', () async {
      await controller.startTwoFactorSetup();

      final result = await controller.confirmTwoFactorSetup('123456');

      expect(result, isTrue);
      expect(controller.enrollment, isNull);
      expect(controller.twoFactorStatus?.isEnabled, isTrue);
      expect(repository.lastCode, '123456');
    });

    test('a rejected code keeps the enrollment so it can be retried', () async {
      await controller.startTwoFactorSetup();
      repository.failure = const AuthFailure(
        'That code did not match.',
        reason: AuthFailureReason.invalidTotpCode,
      );

      final result = await controller.confirmTwoFactorSetup('000000');

      expect(result, isNull);
      expect(controller.enrollment, isNotNull);
      expect(controller.failureReason, AuthFailureReason.invalidTotpCode);
    });

    test(
      'confirming without an enrollment does not call the repository',
      () async {
        final result = await controller.confirmTwoFactorSetup('123456');

        expect(result, isNull);
        expect(repository.calls, isEmpty);
        expect(controller.errorMessage, isNotNull);
      },
    );

    test('discardEnrollment forgets the secret', () async {
      await controller.startTwoFactorSetup();

      controller.discardEnrollment();

      expect(controller.enrollment, isNull);
    });
  });

  group('disabling', () {
    test('requires a code and clears the status', () async {
      repository.twoFactorState = const TwoFactorStatus(
        isEnabled: true,
        factorId: 'factor-1',
      );
      await controller.loadTwoFactorStatus();

      final result = await controller.disableTwoFactor('654321');

      expect(result, isTrue);
      expect(controller.twoFactorStatus?.isEnabled, isFalse);
      expect(repository.lastCode, '654321');
    });

    test('does nothing when no factor is enrolled', () async {
      await controller.loadTwoFactorStatus();

      final result = await controller.disableTwoFactor('654321');

      expect(result, isNull);
      expect(repository.calls, ['twoFactorStatus']);
    });
  });

  group('changePassword', () {
    test('delegates to the repository', () async {
      final result = await controller.changePassword(
        currentPassword: 'Old0Passphrase',
        newPassword: 'New0Passphrase',
      );

      expect(result, isTrue);
      expect(repository.calls, ['updatePassword']);
    });

    test('surfaces a wrong current password with its reason', () async {
      repository.failure = const AuthFailure(
        'That is not your current password.',
        reason: AuthFailureReason.wrongPassword,
      );

      final result = await controller.changePassword(
        currentPassword: 'wrong',
        newPassword: 'New0Passphrase',
      );

      expect(result, isNull);
      expect(controller.failureReason, AuthFailureReason.wrongPassword);
    });
  });
}
