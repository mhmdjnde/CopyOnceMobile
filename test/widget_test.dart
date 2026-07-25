import 'package:copy_once/controllers/auth_controller.dart';
import 'package:copy_once/repositories/auth_repository.dart';
import 'package:copy_once/screens/auth/sign_in_screen.dart';
import 'package:copy_once/screens/auth/sign_up_screen.dart';
import 'package:copy_once/theme/app_theme.dart';
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
      await enterField(tester, 'At least 8 characters', 'secret123');
      await enterField(tester, 'Re-enter your password', 'secret124');
      await tapButton(tester, 'Create Account');

      expect(repository.calls, isEmpty);
      expect(find.text('Passwords do not match.'), findsOneWidget);
    });

    testWidgets('blocks submission when the password is too short', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const SignUpScreen()));

      await enterField(tester, 'you@example.com', 'new@example.com');
      await enterField(tester, 'At least 8 characters', 'short');
      await enterField(tester, 'Re-enter your password', 'short');
      await tapButton(tester, 'Create Account');

      expect(repository.calls, isEmpty);
      expect(find.text('Use at least 8 characters.'), findsOneWidget);
    });

    testWidgets('submits a valid form and forwards the display name', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const SignUpScreen()));

      await enterField(tester, 'How should we greet you?', 'Sam');
      await enterField(tester, 'you@example.com', 'new@example.com');
      await enterField(tester, 'At least 8 characters', 'secret123');
      await enterField(tester, 'Re-enter your password', 'secret123');
      await tapButton(tester, 'Create Account');

      expect(repository.calls, ['signUp']);
      expect(repository.lastEmail, 'new@example.com');
      expect(repository.lastDisplayName, 'Sam');
    });

    testWidgets('shows the confirmation screen when email verification is on', (
      tester,
    ) async {
      repository.signUpOutcome = SignUpOutcome.confirmationRequired;
      await tester.pumpWidget(wrap(const SignUpScreen()));

      await enterField(tester, 'you@example.com', 'new@example.com');
      await enterField(tester, 'At least 8 characters', 'secret123');
      await enterField(tester, 'Re-enter your password', 'secret123');
      await tapButton(tester, 'Create Account');

      expect(find.text('Confirm your email'), findsOneWidget);
      expect(find.textContaining('new@example.com'), findsOneWidget);
    });
  });
}
