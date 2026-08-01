import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The CopyOnce mark, in whichever variant suits the active theme.
///
/// The original asset ships on an opaque near-white plate, which shows up as a
/// white square on a dark background. Both variants here are transparent, and
/// the dark one lifts the ink so a dark-green mark is not drawn on a dark-green
/// ground.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 80});

  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = context.colors.brightness == Brightness.dark;

    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        isDark
            ? 'assets/images/copyonce_logo_dark.png'
            : 'assets/images/copyonce_logo_light.png',
        fit: BoxFit.contain,
        semanticLabel: 'CopyOnce logo',
      ),
    );
  }
}
