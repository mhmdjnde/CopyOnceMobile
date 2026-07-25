import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../repositories/auth_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/auth_scaffold.dart';

/// Collects the code Supabase emailed after sign-up and exchanges it for a
/// session.
///
/// On success the [AuthController] flips to authenticated and the AuthGate
/// swaps in the app, so this screen never navigates forward itself — the user
/// lands in CopyOnce rather than back on the sign-in form.
class VerifyCodeScreen extends StatefulWidget {
  const VerifyCodeScreen({super.key, required this.email});

  /// Address the code was sent to. Shown so the user can spot a typo.
  final String email;

  /// How long before another code can be requested. Long enough to keep users
  /// from burning through the project's email rate limit.
  static const resendCooldown = Duration(seconds: 60);

  @override
  State<VerifyCodeScreen> createState() => _VerifyCodeScreenState();
}

class _VerifyCodeScreenState extends State<VerifyCodeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();

  Timer? _cooldownTimer;
  int _secondsUntilResend = 0;

  /// Guards against the field's onChanged firing a second submit while the
  /// first is still in flight.
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // A code was sent immediately before this screen opened.
    _startCooldown();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() {
      _secondsUntilResend = VerifyCodeScreen.resendCooldown.inSeconds;
    });
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _secondsUntilResend--);
      if (_secondsUntilResend <= 0) timer.cancel();
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    _isSubmitting = true;
    final auth = context.read<AuthController>();
    final verified = await auth.verifySignUpCode(_codeController.text);
    _isSubmitting = false;

    if (!mounted || verified == true) return;

    // A rejected code is worth clearing so the next attempt starts clean; other
    // failures (offline, rate limit) keep it so the user can simply retry.
    if (auth.failureReason == AuthFailureReason.invalidCode) {
      _codeController.clear();
    }
  }

  Future<void> _resend() async {
    FocusScope.of(context).unfocus();
    final auth = context.read<AuthController>();
    final sent = await auth.resendSignUpCode();
    if (!mounted || sent == null) return;

    _codeController.clear();
    _startCooldown();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('New code sent. Check your inbox.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final canResend = _secondsUntilResend <= 0 && !auth.isBusy;

    return AuthScaffold(
      title: 'Enter your code',
      subtitle:
          'We emailed a ${Validators.verificationCodeLength}-digit code to '
          '${widget.email}. Enter it to finish setting up your account.',
      children: [
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (auth.errorMessage != null)
                  AuthErrorBanner(message: auth.errorMessage!),

                VerificationCodeField(
                  controller: _codeController,
                  enabled: !auth.isBusy,
                  onCompleted: (_) => _submit(),
                ),
                const SizedBox(height: AppSpacing.l),

                AuthSubmitButton(
                  label: 'Verify & Continue',
                  isBusy: auth.isBusy,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.m),
        TextButton(
          onPressed: canResend ? _resend : null,
          child: Text(
            canResend
                ? 'Resend code'
                : 'Resend code in ${_secondsUntilResend}s',
          ),
        ),

        const SizedBox(height: AppSpacing.s),
        const Text(
          'Wrong address? Go back and sign up again.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
