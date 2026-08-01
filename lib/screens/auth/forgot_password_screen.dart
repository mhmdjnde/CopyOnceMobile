import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/auth_scaffold.dart';

/// Requests a password-reset email.
///
/// Shows the same confirmation regardless of whether the address exists, so the
/// screen cannot be used to discover which emails have CopyOnce accounts.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController = TextEditingController(
    text: widget.initialEmail ?? '',
  );
  bool _emailSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final sent = await context.read<AuthController>().sendPasswordReset(
      _emailController.text,
    );

    if (!mounted || sent == null) return;
    setState(() => _emailSent = true);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    if (_emailSent) {
      return AuthScaffold(
        title: 'Check your email',
        subtitle:
            'If an account exists for ${_emailController.text.trim()}, '
            'a password reset link is on its way.',
        children: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to Sign In'),
          ),
        ],
      );
    }

    return AuthScaffold(
      title: 'Reset your password',
      subtitle: "Enter your email and we'll send you a reset link.",
      children: [
        Form(
          key: _formKey,
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
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.email],
                prefixIcon: Icons.mail_outline_rounded,
                validator: Validators.email,
                enabled: !auth.isBusy,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AppSpacing.l),

              AuthSubmitButton(
                label: 'Send Reset Link',
                isBusy: auth.isBusy,
                onPressed: _submit,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.m),
        Text(
          'You will stay signed out until you set a new password.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.colors.textHint, fontSize: 13),
        ),
      ],
    );
  }
}
