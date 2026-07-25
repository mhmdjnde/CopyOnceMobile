import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/security_controller.dart';
import '../../repositories/auth_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/auth_scaffold.dart';
import '../../widgets/password_strength_field.dart';

/// Changes the account password, proving the current one first.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscureCurrent = true;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final security = context.read<SecurityController>();
    final changed = await security.changePassword(
      currentPassword: _currentController.text,
      newPassword: _newController.text,
    );

    if (!mounted) return;

    if (changed == true) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Password updated.')));
      return;
    }

    // Only the current-password field is worth clearing: retyping a long new
    // password the user got right is a punishment, not a safeguard.
    if (security.failureReason == AuthFailureReason.wrongPassword) {
      _currentController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final security = context.watch<SecurityController>();
    final email = context.read<AuthController>().currentUser?.email;
    final isWide = MediaQuery.sizeOf(context).width > 600;

    return Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isWide ? 480.0 : double.infinity,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (security.errorMessage != null)
                      AuthErrorBanner(message: security.errorMessage!),

                    AuthTextField(
                      controller: _currentController,
                      label: 'Current password',
                      hintText: 'Your current password',
                      obscureText: _obscureCurrent,
                      autofillHints: const [AutofillHints.password],
                      prefixIcon: Icons.lock_outline_rounded,
                      validator: Validators.requiredPassword,
                      enabled: !security.isBusy,
                      suffixIcon: PasswordVisibilityToggle(
                        isObscured: _obscureCurrent,
                        onToggle: () =>
                            setState(() => _obscureCurrent = !_obscureCurrent),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.l),

                    const Divider(),
                    const SizedBox(height: AppSpacing.l),

                    PasswordStrengthField(
                      controller: _newController,
                      label: 'New password',
                      email: email,
                      enabled: !security.isBusy,
                    ),
                    const SizedBox(height: AppSpacing.m),

                    AuthTextField(
                      controller: _confirmController,
                      label: 'Confirm new password',
                      hintText: 'Re-enter your new password',
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      prefixIcon: Icons.lock_outline_rounded,
                      enabled: !security.isBusy,
                      onFieldSubmitted: (_) => _submit(),
                      validator: (value) => Validators.confirmPassword(
                        value,
                        _newController.text,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.l),

                    AuthSubmitButton(
                      label: 'Update password',
                      isBusy: security.isBusy,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: AppSpacing.m),

                    const Text(
                      'Other devices stay signed in. Sign out of them from '
                      'Settings if you think someone else knew your old '
                      'password.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
