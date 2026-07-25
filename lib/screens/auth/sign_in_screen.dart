import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../repositories/auth_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/auth_scaffold.dart';
import 'forgot_password_screen.dart';
import 'sign_up_screen.dart';
import 'verify_code_screen.dart';

/// Email + password sign-in.
///
/// On success the [AuthController] emits an authenticated state and the
/// [AuthGate] swaps in the main app — this screen does not navigate itself.
///
/// The one exception is an account that signed up but never entered its code:
/// that gets a fresh code and the [VerifyCodeScreen], so the flow can be
/// finished instead of dead-ending on an error.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthController>();
    final signedIn = await auth.signIn(
      email: _emailController.text,
      password: _passwordController.text,
    );

    // Success is handled by the gate; other failures just show their banner.
    if (!mounted ||
        signedIn != null ||
        auth.failureReason != AuthFailureReason.unconfirmedEmail) {
      return;
    }

    final email = _emailController.text.trim();
    final sent = await auth.resendSignUpCode(email: email);
    if (!mounted || sent == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => VerifyCodeScreen(email: email)),
    );
  }

  void _goToSignUp() {
    context.read<AuthController>().clearError();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const SignUpScreen()),
    );
  }

  void _goToForgotPassword() {
    context.read<AuthController>().clearError();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ForgotPasswordScreen(initialEmail: _emailController.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Sign in to sync your clipboard across devices.',
      children: [
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (auth.errorMessage != null)
                  AuthErrorBanner(message: auth.errorMessage!),

                AuthTextField(
                  controller: _emailController,
                  label: 'Email',
                  hintText: 'you@example.com',
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  prefixIcon: Icons.mail_outline_rounded,
                  validator: Validators.email,
                  enabled: !auth.isBusy,
                ),
                const SizedBox(height: AppSpacing.m),

                AuthTextField(
                  controller: _passwordController,
                  label: 'Password',
                  hintText: 'Your password',
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  prefixIcon: Icons.lock_outline_rounded,
                  validator: Validators.requiredPassword,
                  enabled: !auth.isBusy,
                  onFieldSubmitted: (_) => _submit(),
                  suffixIcon: PasswordVisibilityToggle(
                    isObscured: _obscurePassword,
                    onToggle: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),

                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: auth.isBusy ? null : _goToForgotPassword,
                    child: const Text('Forgot password?'),
                  ),
                ),
                const SizedBox(height: AppSpacing.s),

                AuthSubmitButton(
                  label: 'Sign In',
                  isBusy: auth.isBusy,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.l),
        AuthFooterPrompt(
          question: "Don't have an account?",
          actionLabel: 'Sign up',
          onPressed: auth.isBusy ? null : _goToSignUp,
        ),
      ],
    );
  }
}
