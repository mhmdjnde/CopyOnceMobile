import 'package:flutter/material.dart';

/// All colors used in CopyOnce, derived from the logo palette:
/// muted sage green, warm beige, soft off-white, dark green-gray.
abstract class AppColors {
  // Brand
  static const Color primary = Color(0xFF2B392B);
  static const Color accent = Color(0xFF7B9E7B);

  // Backgrounds
  static const Color background = Color(0xFFF6F4EF);
  static const Color surface = Color(0xFFEBE6DA);
  static const Color card = Color(0xFFFFFFFF);

  // Text
  static const Color textPrimary = Color(0xFF1C2B1C);
  static const Color textSecondary = Color(0xFF5A6E5A);
  static const Color textHint = Color(0xFF98A898);

  // Semantic
  static const Color divider = Color(0xFFE2DDD4);
  static const Color error = Color(0xFFB5432A);
  static const Color link = Color(0xFF3D6B8E);
  static const Color white = Color(0xFFFFFFFF);
  static const Color success = Color(0xFF4A8A5A);

  // Pre-computed transparent tints
  /// Accent at ~16 % opacity — navigation indicator.
  static const Color accentSubtle = Color(0x287B9E7B);

  /// Primary at ~8 % opacity — text-type icon background.
  static const Color primarySubtle = Color(0x142B392B);

  /// Link at ~10 % opacity — link-type icon background.
  static const Color linkSubtle = Color(0x1A3D6B8E);

  /// Accent at ~10 % opacity — image-type icon background.
  static const Color accentImageSubtle = Color(0x1A7B9E7B);

  /// Success at ~12 % opacity — device online indicator background.
  static const Color successSubtle = Color(0x1E4A8A5A);
}
