import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'auth/sign_in_screen.dart';
import 'auth/sign_up_screen.dart';
import '../widgets/app_logo.dart';

/// Single-step onboarding that introduces the app's core value proposition,
/// then hands off to account creation.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  void _getStarted(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, animation, _) =>
            FadeTransition(opacity: animation, child: const SignUpScreen()),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  void _signIn(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SignInScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final contentWidth = screenWidth > 600 ? 480.0 : double.infinity;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),

                  // Logo
                  AppLogo(size: 80),

                  const SizedBox(height: AppSpacing.xl),

                  // Headline
                  Text(
                    'Copy once,\naccess everywhere.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary,
                      height: 1.2,
                      letterSpacing: -0.8,
                    ),
                  ),

                  const SizedBox(height: AppSpacing.m),

                  // Subtitle
                  Text(
                    'Your clipboard, synced instantly across\niPhone, Android, and desktop.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: context.colors.textSecondary,
                      height: 1.6,
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xxl),

                  // Feature bullets
                  const _FeatureBullet(
                    icon: Icons.sync_rounded,
                    label: 'Sync text, links, and images',
                  ),
                  const SizedBox(height: AppSpacing.m),
                  const _FeatureBullet(
                    icon: Icons.devices_rounded,
                    label: 'Works across all your devices',
                  ),
                  const SizedBox(height: AppSpacing.m),
                  // Not "end-to-end encrypted": content is readable at rest by
                  // the database. See the note atop 0002_clipboard.sql. Claim
                  // only what the backend actually does — if end-to-end
                  // encryption lands, this line can change with it.
                  const _FeatureBullet(
                    icon: Icons.lock_outline_rounded,
                    label: 'Private to you, encrypted in transit',
                  ),

                  const Spacer(flex: 2),

                  // CTA
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _getStarted(context),
                      child: const Text('Get Started'),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.s),

                  // Secondary path for returning users
                  TextButton(
                    onPressed: () => _signIn(context),
                    child: const Text('I already have an account'),
                  ),

                  const SizedBox(height: AppSpacing.l),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureBullet extends StatelessWidget {
  const _FeatureBullet({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: context.colors.accentSubtle,
            borderRadius: BorderRadius.circular(AppRadius.s),
          ),
          child: Icon(icon, size: 16, color: context.colors.accent),
        ),
        const SizedBox(width: AppSpacing.m),
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            color: context.colors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
