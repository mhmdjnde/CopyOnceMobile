import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_scaffold.dart';

/// Shown after sign-up when the project requires email confirmation before
/// issuing a session.
class CheckEmailScreen extends StatelessWidget {
  const CheckEmailScreen({super.key, required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Confirm your email',
      subtitle:
          'We sent a confirmation link to $email. '
          'Open it to activate your account, then sign in.',
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.l),
          decoration: BoxDecoration(
            color: AppColors.accentSubtle,
            borderRadius: BorderRadius.circular(AppRadius.l),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.mark_email_unread_outlined,
                color: AppColors.accent,
                size: 24,
              ),
              SizedBox(width: AppSpacing.m),
              Expanded(
                child: Text(
                  "Can't find it? Check your spam folder.",
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to Sign In'),
        ),
      ],
    );
  }
}
