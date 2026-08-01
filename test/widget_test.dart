import 'package:copy_once/controllers/auth_controller.dart';
import 'package:copy_once/repositories/auth_repository.dart';
import 'package:copy_once/screens/auth/sign_in_screen.dart';
import 'package:copy_once/screens/auth/sign_up_screen.dart';
import 'package:copy_once/screens/auth/verify_code_screen.dart';
import 'package:copy_once/theme/app_theme.dart';
import 'package:copy_once/utils/password_policy.dart';
import 'package:copy_once/utils/validators.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

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

  Widget wrap(Widget child) {
    return ChangeNotifierProvider<AuthController>.value(
      value: controller,
      child: MaterialApp(theme: AppTheme.light, home: child),
    );
  }

  Future<void> enterField(
    WidgetTester tester,
    String label,
    String value,
  ) async {
    await tester.enterText(
      find.widgetWithText(TextFormField, label).first,
      value,
    );
  }

  /// Replaces the tree so [State.dispose] runs, cancelling the resend
  /// countdown. Without this the test ends with a pending timer.
  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  /// Scrolls the button into view before tapping — the sign-up form is taller
  /// than the default test viewport.
  Future<void> tapButton(WidgetTester tester, String label) async {
    final button = find.widgetWithText(ElevatedButton, label);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  group('SignInScreen', () {
    testWidgets('shows email and password fields', (tester) async {
      await tester.pumpWidget(wrap(const SignInScreen()));

      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Sign In'), findsOneWidget);
    });

    testWidgets('does not call the repository when the form is invalid', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const SignInScreen()));

      await tapButton(tester, 'Sign In');

      expect(repository.calls, isEmpty);
      expect(find.text('Enter your email address.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
    });

    testWidgets('rejects a malformed email before hitting the network', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const SignInScreen()));

      await enterField(tester, 'you@example.com', 'not-an-email');
      await enterField(tester, 'Your password', 'secret123');
      await tapButton(tester, 'Sign In');

      expect(repository.calls, isEmpty);
      expect(find.text('Enter a valid email address.'), findsOneWidget);
    });

    testWidgets('submits valid credentials to the repository', (tester) async {
      await tester.pumpWidget(wrap(const SignInScreen()));

      await enterField(tester, 'you@example.com', 'user@example.com');
      await enterField(tester, 'Your password', 'secret123');
      await tapButton(tester, 'Sign In');

      expect(repository.calls, ['signIn']);
      expect(repository.lastEmail, 'user@example.com');
    });

    testWidgets('shows the error banner when sign-in fails', (tester) async {
      repository.failure = const AuthFailure('Incorrect email or password.');
      await tester.pumpWidget(wrap(const SignInScreen()));

      await enterField(tester, 'you@example.com', 'user@example.com');
      await enterField(tester, 'Your password', 'wrongpass');
      await tapButton(tester, 'Sign In');

      expect(find.text('Incorrect email or password.'), findsOneWidget);
    });

    testWidgets('obscures the password until the toggle is tapped', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const SignInScreen()));

      TextField passwordField() => tester.widget<TextField>(
        find.descendant(
          of: find.widgetWithText(TextFormField, 'Your password'),
          matching: find.byType(TextField),
        ),
      );

      expect(passwordField().obscureText, isTrue);

      await tester.tap(find.byTooltip('Show password'));
      await tester.pumpAndSettle();

      expect(passwordField().obscureText, isFalse);
    });
  });

  group('SignUpScreen', () {
    testWidgets('shows the account creation form', (tester) async {
      await tester.pumpWidget(wrap(const SignUpScreen()));

      expect(find.text('Create your account'), findsOneWidget);
      expect(find.text('Confirm password'), findsOneWidget);
      expect(
        find.widgetWithText(ElevatedButton, 'Create Account'),
        findsOneWidget,
      );
    });

    testWidgets('blocks submission when the passwords differ', (tester) async {
      await tester.pumpWidget(wrap(const SignUpScreen()));

      await enterField(tester, 'you@example.com', 'new@example.com');
      await enterField(tester, PasswordRule.length.label, 'Str0ngPassphrase');
      await enterField(tester, 'Re-enter your password', 'Str0ngPassphras3');
      await tapButton(tester, 'Create Account');

      expect(repository.calls, isEmpty);
      expect(find.text('Passwords do not match.'), findsOneWidget);
    });

    testWidgets('blocks submission when the password is too short', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const SignUpScreen()));

      await enterField(tester, 'you@example.com', 'new@example.com');
      await enterField(tester, PasswordRule.length.label, 'Short1');
      await enterField(tester, 'Re-enter your password', 'Short1');
      await tapButton(tester, 'Create Account');

      expect(repository.calls, isEmpty);
      expect(
        find.text('Use at least ${PasswordPolicy.minLength} characters.'),
        findsOneWidget,
      );
    });

    testWidgets('submits a valid form and forwards the display name', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const SignUpScreen()));

      await enterField(tester, 'How should we greet you?', 'Sam');
      await enterField(tester, 'you@example.com', 'new@example.com');
      await enterField(tester, PasswordRule.length.label, 'Str0ngPassphrase');
      await enterField(tester, 'Re-enter your password', 'Str0ngPassphrase');
      await tapButton(tester, 'Create Account');

      expect(repository.calls, ['signUp']);
      expect(repository.lastEmail, 'new@example.com');
      expect(repository.lastDisplayName, 'Sam');
    });

    testWidgets('opens the code screen when a verification code was sent', (
      tester,
    ) async {
      repository.signUpOutcome = SignUpOutcome.codeSent;
      await tester.pumpWidget(wrap(const SignUpScreen()));

      await enterField(tester, 'you@example.com', 'new@example.com');
      await enterField(tester, PasswordRule.length.label, 'Str0ngPassphrase');
      await enterField(tester, 'Re-enter your password', 'Str0ngPassphrase');
      await tapButton(tester, 'Create Account');

      expect(find.text('Enter your code'), findsOneWidget);
      expect(find.textContaining('new@example.com'), findsOneWidget);

      await disposeTree(tester);
    });
  });

  group('VerifyCodeScreen', () {
    // Derived so these follow Validators.verificationCodeLength rather than
    // pinning a length that lives in the Supabase project settings.
    final validCode = '1' * Validators.verificationCodeLength;

    /// Puts the controller in the state the screen expects — signed up, waiting
    /// on a code — then shows it.
    Future<void> pumpVerifyScreen(WidgetTester tester) async {
      repository.signUpOutcome = SignUpOutcome.codeSent;
      await controller.signUp(email: 'new@example.com', password: 'secret123');
      repository.calls.clear();
      await tester.pumpWidget(
        wrap(const VerifyCodeScreen(email: 'new@example.com')),
      );
    }

    testWidgets('verifies as soon as the code is complete', (tester) async {
      await pumpVerifyScreen(tester);

      await tester.enterText(find.byType(TextFormField), validCode);
      await tester.pump();

      expect(repository.calls, ['verifySignUpCode']);
      expect(repository.lastCode, validCode);

      await disposeTree(tester);
    });

    testWidgets('rejects a short code without calling the repository', (
      tester,
    ) async {
      await pumpVerifyScreen(tester);

      await tester.enterText(find.byType(TextFormField), '123');
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Verify & Continue'),
      );
      await tester.pump();

      expect(repository.calls, isEmpty);
      expect(
        find.text('The code is ${Validators.verificationCodeLength} digits.'),
        findsOneWidget,
      );

      await disposeTree(tester);
    });

    testWidgets('shows the failure and clears the field on a bad code', (
      tester,
    ) async {
      await pumpVerifyScreen(tester);
      repository.failure = const AuthFailure(
        'That code is incorrect or has expired. Request a new one.',
        reason: AuthFailureReason.invalidCode,
      );

      await tester.enterText(
        find.byType(TextFormField),
        '0' * Validators.verificationCodeLength,
      );
      await tester.pump();

      expect(
        find.text('That code is incorrect or has expired. Request a new one.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty,
      );

      await disposeTree(tester);
    });

    testWidgets('holds the resend button on a cooldown', (tester) async {
      await pumpVerifyScreen(tester);

      final resend = find.widgetWithText(TextButton, 'Resend code in 60s');
      expect(resend, findsOneWidget);
      expect(tester.widget<TextButton>(resend).onPressed, isNull);

      await disposeTree(tester);
    });
  });
}
