import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/auth_scaffold.dart';

/// Second step of sign-in for accounts with an authenticator.
///
/// Shown by the AuthGate whenever the session is password-only, so it cannot be
/// skipped by navigating around it. Verifying steps the session up and the gate
/// swaps in the app; the only way past it otherwise is signing out.
class MfaChallengeScreen extends StatefulWidget {
  const MfaChallengeScreen({super.key});

  @override
  State<MfaChallengeScreen> createState() => _MfaChallengeScreenState();
}

class _MfaChallengeScreenState extends State<MfaChallengeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    _isSubmitting = true;
    final verified = await context.read<AuthController>().verifySecondFactor(
      _codeController.text,
    );
    _isSubmitting = false;

    // Codes are single-use, so a rejected one is always worth clearing.
    if (mounted && verified != true) _codeController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return AuthScaffold(
      title: 'Two-factor authentication',
      subtitle:
          'Open your authenticator app and enter the current code for '
          'CopyOnce.',
      showBackButton: false,
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (auth.errorMessage != null)
                AuthErrorBanner(message: auth.errorMessage!),

              VerificationCodeField(
                controller: _codeController,
                enabled: !auth.isBusy,
                length: Validators.authenticatorCodeLength,
                validator: Validators.authenticatorCode,
                onCompleted: (_) => _submit(),
              ),
              const SizedBox(height: AppSpacing.l),

              AuthSubmitButton(
                label: 'Verify',
                isBusy: auth.isBusy,
                onPressed: _submit,
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.l),
        Container(
          padding: const EdgeInsets.all(AppSpacing.m),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.m),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
              SizedBox(width: AppSpacing.s),
              Expanded(
                child: Text(
                  'Codes change every 30 seconds. If yours keeps being '
                  'rejected, check that your phone clock is set automatically.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.m),
        TextButton(
          onPressed: auth.isBusy
              ? null
              : () => context.read<AuthController>().signOut(),
          child: const Text('Sign in with a different account'),
        ),
      ],
    );
  }
}
