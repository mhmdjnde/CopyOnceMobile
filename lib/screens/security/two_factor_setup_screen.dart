import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../controllers/security_controller.dart';
import '../../models/two_factor.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/auth_scaffold.dart';

/// Walks through adding an authenticator: scan, then confirm a code.
///
/// Nothing is enabled until the code is confirmed, so backing out at any point
/// leaves the account unchanged.
class TwoFactorSetupScreen extends StatefulWidget {
  const TwoFactorSetupScreen({super.key});

  @override
  State<TwoFactorSetupScreen> createState() => _TwoFactorSetupScreenState();
}

class _TwoFactorSetupScreenState extends State<TwoFactorSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Enroll immediately so the QR is on screen when the user reaches for their
    // phone, rather than behind another tap.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SecurityController>().startTwoFactorSetup();
    });
  }

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
    final security = context.read<SecurityController>();
    final confirmed = await security.confirmTwoFactorSetup(
      _codeController.text,
    );
    _isSubmitting = false;

    if (!mounted) return;

    if (confirmed == true) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Two-factor authentication is on.')),
      );
      return;
    }

    _codeController.clear();
  }

  Future<void> _copySecret(String secret) async {
    await Clipboard.setData(ClipboardData(text: secret));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Setup key copied.')));
  }

  @override
  Widget build(BuildContext context) {
    final security = context.watch<SecurityController>();
    final enrollment = security.enrollment;
    final isWide = MediaQuery.sizeOf(context).width > 600;

    return Scaffold(
      appBar: AppBar(title: const Text('Two-factor authentication')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isWide ? 480.0 : double.infinity,
              ),
              child: switch ((enrollment, security.isBusy)) {
                (null, true) => const _SetupLoading(),
                (null, false) => _SetupFailed(
                  message: security.errorMessage,
                  onRetry: () =>
                      context.read<SecurityController>().startTwoFactorSetup(),
                ),
                (final TotpEnrollment e, _) => _SetupSteps(
                  enrollment: e,
                  formKey: _formKey,
                  codeController: _codeController,
                  isBusy: security.isBusy,
                  errorMessage: security.errorMessage,
                  onSubmit: _submit,
                  onCopySecret: () => _copySecret(e.secret),
                ),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SetupLoading extends StatelessWidget {
  const _SetupLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Column(
        children: [
          CircularProgressIndicator(),
          SizedBox(height: AppSpacing.l),
          Text(
            'Preparing your setup key…',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _SetupFailed extends StatelessWidget {
  const _SetupFailed({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          const Icon(
            Icons.shield_outlined,
            size: 40,
            color: AppColors.textHint,
          ),
          const SizedBox(height: AppSpacing.m),
          Text(
            message ?? 'Could not start setup.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.l),
          ElevatedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _SetupSteps extends StatelessWidget {
  const _SetupSteps({
    required this.enrollment,
    required this.formKey,
    required this.codeController,
    required this.isBusy,
    required this.errorMessage,
    required this.onSubmit,
    required this.onCopySecret,
  });

  final TotpEnrollment enrollment;
  final GlobalKey<FormState> formKey;
  final TextEditingController codeController;
  final bool isBusy;
  final String? errorMessage;
  final Future<void> Function() onSubmit;
  final VoidCallback onCopySecret;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (errorMessage != null) AuthErrorBanner(message: errorMessage!),

        const _StepHeader(
          step: 1,
          title: 'Scan with your authenticator',
          detail:
              'Google Authenticator, Authy, 1Password — any TOTP app works.',
        ),
        const SizedBox(height: AppSpacing.m),

        Center(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.m),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(AppRadius.l),
              border: Border.all(color: AppColors.divider),
            ),
            child: QrImageView(
              data: enrollment.otpauthUri,
              size: 200,
              backgroundColor: AppColors.white,
              // Brand-matched, kept dark enough for reliable scanning.
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: AppColors.primary,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.l),

        // Manual entry for anyone whose authenticator lives on this same phone.
        Container(
          padding: const EdgeInsets.all(AppSpacing.m),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.m),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Can't scan? Enter this key instead",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.s),
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      enrollment.formattedSecret,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        letterSpacing: 1,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onCopySecret,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    tooltip: 'Copy setup key',
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        const _StepHeader(
          step: 2,
          title: 'Enter the 6-digit code',
          detail: 'This proves the app is in sync before we turn 2FA on.',
        ),
        const SizedBox(height: AppSpacing.m),

        Form(
          key: formKey,
          child: VerificationCodeField(
            controller: codeController,
            enabled: !isBusy,
            length: Validators.authenticatorCodeLength,
            validator: Validators.authenticatorCode,
            onCompleted: (_) => onSubmit(),
          ),
        ),
        const SizedBox(height: AppSpacing.l),

        AuthSubmitButton(
          label: 'Turn on 2FA',
          isBusy: isBusy,
          onPressed: onSubmit,
        ),
        const SizedBox(height: AppSpacing.m),

        const Text(
          'Keep your authenticator backed up. Without it — and without this '
          'setup key — you will not be able to sign in.',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.step,
    required this.title,
    required this.detail,
  });

  final int step;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 24,
          width: 24,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.accentSubtle,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$step',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.m),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
