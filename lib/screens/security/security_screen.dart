import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/security_controller.dart';
import '../../models/two_factor.dart';
import '../../repositories/auth_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/auth_scaffold.dart';
import 'change_password_screen.dart';
import 'two_factor_setup_screen.dart';
import 'scan_login_screen.dart';

/// Account security: password and two-factor authentication.
///
/// Owns a [SecurityController] for the duration of the flow — enrollment
/// secrets are dropped when this route is popped rather than living for the
/// lifetime of the app.
class SecurityScreen extends StatelessWidget {
  const SecurityScreen({super.key});

  /// Route for this screen with its controller attached.
  static Route<void> route() {
    return MaterialPageRoute<void>(
      builder: (context) => ChangeNotifierProvider(
        create: (_) => SecurityController(context.read<AuthRepository>()),
        child: const _SecurityView(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const _SecurityView();
}

class _SecurityView extends StatefulWidget {
  const _SecurityView();

  @override
  State<_SecurityView> createState() => _SecurityViewState();
}

class _SecurityViewState extends State<_SecurityView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SecurityController>().loadTwoFactorStatus();
    });
  }

  Future<void> _openTwoFactorSetup() async {
    final security = context.read<SecurityController>();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider.value(
          value: security,
          child: const TwoFactorSetupScreen(),
        ),
      ),
    );
    // Setup may have been abandoned midway; drop any half-finished secret and
    // re-read the real state rather than trusting what the screen left behind.
    security.discardEnrollment();
    if (mounted) await security.loadTwoFactorStatus();
  }

  Future<void> _openChangePassword() async {
    final security = context.read<SecurityController>();
    security.clearError();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider.value(
          value: security,
          child: const ChangePasswordScreen(),
        ),
      ),
    );
  }

  Future<void> _confirmDisable() async {
    final security = context.read<SecurityController>();
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _DisableTwoFactorDialog(),
    );
    if (code == null || !mounted) return;

    final disabled = await security.disableTwoFactor(code);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          disabled == true
              ? 'Two-factor authentication is off.'
              : security.errorMessage ?? 'Could not turn off 2FA.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final security = context.watch<SecurityController>();
    final status = security.twoFactorStatus;
    final contentWidth = MediaQuery.sizeOf(context).width > 600
        ? 560.0
        : double.infinity;

    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentWidth),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.m),
            children: [
              _TwoFactorCard(
                status: status,
                isBusy: security.isBusy,
                onEnable: _openTwoFactorSetup,
                onDisable: _confirmDisable,
              ),
              const SizedBox(height: AppSpacing.l),

              const _SectionLabel('Password'),
              Card(
                child: ListTile(
                  leading: Icon(
                    Icons.password_rounded,
                    color: context.colors.textSecondary,
                    size: 20,
                  ),
                  title: const Text('Change password'),
                  subtitle: const Text('Requires your current password'),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: context.colors.textHint,
                    size: 18,
                  ),
                  onTap: security.isBusy ? null : _openChangePassword,
                ),
              ),
              const SizedBox(height: AppSpacing.l),

              const _SectionLabel('Other devices'),
              Card(
                child: ListTile(
                  leading: Icon(
                    Icons.qr_code_scanner_rounded,
                    color: context.colors.textSecondary,
                    size: 20,
                  ),
                  title: const Text('Scan to sign in'),
                  subtitle: const Text(
                    'Sign in on a computer by scanning its code',
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: context.colors.textHint,
                    size: 18,
                  ),
                  onTap: () => ScanLoginScreen.open(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Two-factor state as a single card whose whole look changes with the state —
/// on reads as protected, off reads as an invitation.
class _TwoFactorCard extends StatelessWidget {
  const _TwoFactorCard({
    required this.status,
    required this.isBusy,
    required this.onEnable,
    required this.onDisable,
  });

  final TwoFactorStatus? status;
  final bool isBusy;
  final VoidCallback onEnable;
  final VoidCallback onDisable;

  @override
  Widget build(BuildContext context) {
    final isOn = status?.isEnabled ?? false;
    final isUnknown = status == null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 40,
                  width: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isOn
                        ? context.colors.successSubtle
                        : context.colors.primarySubtle,
                    borderRadius: BorderRadius.circular(AppRadius.m),
                  ),
                  child: Icon(
                    isOn ? Icons.verified_user_rounded : Icons.shield_outlined,
                    size: 20,
                    color: isOn
                        ? context.colors.success
                        : context.colors.textSecondary,
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Two-factor authentication',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: context.colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isUnknown
                            ? 'Checking…'
                            : isOn
                            ? 'On — a code is required at every sign-in'
                            : 'Off — your password is the only thing '
                                  'protecting your clipboard',
                        style: TextStyle(
                          fontSize: 13,
                          color: isOn
                              ? context.colors.success
                              : context.colors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.m),

            if (isUnknown)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.s),
                  child: SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (isOn)
              OutlinedButton(
                onPressed: isBusy ? null : onDisable,
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.colors.error,
                  side: BorderSide(color: context.colors.divider),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.l),
                  ),
                ),
                child: const Text('Turn off'),
              )
            else
              ElevatedButton(
                onPressed: isBusy ? null : onEnable,
                child: const Text('Set up authenticator'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Asks for a current code before switching 2FA off, so a borrowed unlocked
/// phone cannot quietly weaken the account.
class _DisableTwoFactorDialog extends StatefulWidget {
  const _DisableTwoFactorDialog();

  @override
  State<_DisableTwoFactorDialog> createState() =>
      _DisableTwoFactorDialogState();
}

class _DisableTwoFactorDialogState extends State<_DisableTwoFactorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_codeController.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Turn off 2FA?'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Your password alone will protect your clipboard. Enter a '
              'current code to confirm it is you.',
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.l),
            VerificationCodeField(
              controller: _codeController,
              enabled: true,
              length: Validators.authenticatorCodeLength,
              validator: Validators.authenticatorCode,
              onCompleted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          style: TextButton.styleFrom(foregroundColor: context.colors.error),
          child: const Text('Turn off'),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.s),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: context.colors.textHint,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}
