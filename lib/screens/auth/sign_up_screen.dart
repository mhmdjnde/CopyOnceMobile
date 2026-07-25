import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/auth_scaffold.dart';
import 'check_email_screen.dart';
import 'sign_in_screen.dart';

/// Account creation with email + password.
///
/// If the Supabase project requires email confirmation, sign-up returns no
/// session and this screen pushes [CheckEmailScreen]. Otherwise the
/// [AuthController] flips to authenticated and the gate swaps in the app.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final signedIn = await context.read<AuthController>().signUp(
      email: _emailController.text,
      password: _passwordController.text,
      displayName: _nameController.text,
    );

    // null means the attempt failed; the error banner already shows why.
    if (!mounted || signedIn == null || signedIn) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CheckEmailScreen(email: _emailController.text.trim()),
      ),
    );
  }

  void _goToSignIn() {
    context.read<AuthController>().clearError();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return AuthScaffold(
      title: 'Create your account',
      subtitle: 'Start syncing your clipboard everywhere.',
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
                  controller: _nameController,
                  label: 'Name (optional)',
                  hintText: 'How should we greet you?',
                  keyboardType: TextInputType.name,
                  autofillHints: const [AutofillHints.name],
                  prefixIcon: Icons.person_outline_rounded,
                  validator: Validators.displayName,
                  enabled: !auth.isBusy,
                ),
                const SizedBox(height: AppSpacing.m),

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
                  hintText:
                      'At least ${Validators.minPasswordLength} characters',
                  obscureText: _obscurePassword,
                  autofillHints: const [AutofillHints.newPassword],
                  prefixIcon: Icons.lock_outline_rounded,
                  validator: Validators.password,
                  enabled: !auth.isBusy,
                  suffixIcon: PasswordVisibilityToggle(
                    isObscured: _obscurePassword,
                    onToggle: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                const SizedBox(height: AppSpacing.m),

                AuthTextField(
                  controller: _confirmController,
                  label: 'Confirm password',
                  hintText: 'Re-enter your password',
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  prefixIcon: Icons.lock_outline_rounded,
                  enabled: !auth.isBusy,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (value) => Validators.confirmPassword(
                    value,
                    _passwordController.text,
                  ),
                ),
                const SizedBox(height: AppSpacing.l),

                AuthSubmitButton(
                  label: 'Create Account',
                  isBusy: auth.isBusy,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.l),
        AuthFooterPrompt(
          question: 'Already have an account?',
          actionLabel: 'Sign in',
          onPressed: auth.isBusy ? null : _goToSignIn,
        ),
      ],
    );
  }
}
