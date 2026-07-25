import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/auth_controller.dart';
import '../screens/onboarding_screen.dart';
import '../screens/splash_screen.dart';
import 'main_navigation.dart';

/// Root route. Decides between the splash, the signed-out flow, and the app.
///
/// This is the only place that decides what a user sees based on their session,
/// so no screen has to guard itself. Because it is the first route, clearing the
/// navigator back to it also discards any auth screens that were pushed on top.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  /// How long the branded splash stays up before routing, so a fast session
  /// restore does not make it flash.
  static const splashDuration = Duration(milliseconds: 2400);

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Timer? _splashTimer;
  bool _splashElapsed = false;
  AuthStatus? _lastStatus;

  @override
  void initState() {
    super.initState();
    _splashTimer = Timer(AuthGate.splashDuration, () {
      if (mounted) setState(() => _splashElapsed = true);
    });
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    super.dispose();
  }

  /// Drops any routes pushed above the gate (sign-in, sign-up, reset) so the
  /// new branch is what the user actually sees.
  void _resetNavigationStack() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final status = context.watch<AuthController>().status;

    if (status != _lastStatus) {
      final isFirstResolve = _lastStatus == null;
      _lastStatus = status;
      if (!isFirstResolve) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _resetNavigationStack();
        });
      }
    }

    if (!_splashElapsed || status == AuthStatus.unknown) {
      return const SplashScreen();
    }

    return switch (status) {
      AuthStatus.authenticated => const MainNavigation(),
      _ => const OnboardingScreen(),
    };
  }
}
