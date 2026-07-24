import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../navigation/main_navigation.dart';

/// Single-step onboarding that introduces the app's core value proposition.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  void _getStarted(BuildContext context) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, animation, __) =>
            FadeTransition(opacity: animation, child: const MainNavigation()),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final contentWidth = screenWidth > 600 ? 480.0 : double.infinity;

    return Scaffold(
      backgroundColor: AppColors.background,
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
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: Image.asset(
                      'assets/images/copyonce_logo.png',
                      fit: BoxFit.contain,
                      semanticLabel: 'CopyOnce logo',
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  // Headline
                  const Text(
                    'Copy once,\naccess everywhere.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      height: 1.2,
                      letterSpacing: -0.8,
                    ),
                  ),

                  const SizedBox(height: AppSpacing.m),

                  // Subtitle
                  const Text(
                    'Your clipboard, synced instantly across\niPhone, Android, and desktop.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textSecondary,
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
                  const _FeatureBullet(
                    icon: Icons.lock_outline_rounded,
                    label: 'Private and end-to-end encrypted',
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
            color: AppColors.accentSubtle,
            borderRadius: BorderRadius.circular(AppRadius.s),
          ),
          child: Icon(icon, size: 16, color: AppColors.accent),
        ),
        const SizedBox(width: AppSpacing.m),
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
