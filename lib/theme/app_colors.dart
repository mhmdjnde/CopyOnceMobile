import 'package:flutter/material.dart';

/// The colours CopyOnce uses, as a theme extension so light and dark resolve
/// from the same names.
///
/// Read through `context.colors` rather than referring to a palette directly —
/// that is what makes a widget follow the active theme instead of pinning
/// itself to one. The web client mirrors these values in
/// `web/src/app/globals.css`; those two files are the design system, and there
/// is no third place to look.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brightness,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.background,
    required this.surface,
    required this.card,
    required this.textPrimary,
    required this.textSecondary,
    required this.textHint,
    required this.divider,
    required this.error,
    required this.warning,
    required this.link,
    required this.success,
    required this.accentSubtle,
    required this.primarySubtle,
    required this.linkSubtle,
    required this.accentImageSubtle,
    required this.successSubtle,
  });

  final Brightness brightness;

  /// Buttons, selected states, and anything that should read as CopyOnce.
  final Color primary;

  /// Foreground on [primary]. White on light, near-black on dark: a dark green
  /// button cannot sit on a dark ground, so in dark mode primary lightens and
  /// this darkens to meet it.
  final Color onPrimary;

  final Color accent;

  final Color background;
  final Color surface;
  final Color card;

  final Color textPrimary;
  final Color textSecondary;
  final Color textHint;

  final Color divider;
  final Color error;

  /// "Not wrong yet, but not good either" — password strength, sync warnings.
  final Color warning;
  final Color link;
  final Color success;

  // Pre-computed tints. Alphas run higher in dark mode because a wash that
  // reads clearly over beige disappears over near-black.
  final Color accentSubtle;
  final Color primarySubtle;
  final Color linkSubtle;
  final Color accentImageSubtle;
  final Color successSubtle;

  /// The original palette, derived from the logo: muted sage, warm beige, soft
  /// off-white, dark green-grey.
  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    primary: Color(0xFF2B392B),
    onPrimary: Color(0xFFFFFFFF),
    accent: Color(0xFF7B9E7B),
    background: Color(0xFFF6F4EF),
    surface: Color(0xFFEBE6DA),
    card: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF1C2B1C),
    textSecondary: Color(0xFF5A6E5A),
    textHint: Color(0xFF98A898),
    divider: Color(0xFFE2DDD4),
    error: Color(0xFFB5432A),
    warning: Color(0xFFC0862E),
    link: Color(0xFF3D6B8E),
    success: Color(0xFF4A8A5A),
    accentSubtle: Color(0x287B9E7B),
    primarySubtle: Color(0x142B392B),
    linkSubtle: Color(0x1A3D6B8E),
    accentImageSubtle: Color(0x1A7B9E7B),
    successSubtle: Color(0x1E4A8A5A),
  );

  /// The same hues at night: grounds darkened, ink lifted, sage brightened so
  /// it still carries against a dark background instead of sinking into it.
  static const AppPalette dark = AppPalette(
    brightness: Brightness.dark,
    primary: Color(0xFF9CC49C),
    onPrimary: Color(0xFF10140F),
    accent: Color(0xFF9CC49C),
    background: Color(0xFF141814),
    surface: Color(0xFF1F251F),
    card: Color(0xFF1A201A),
    textPrimary: Color(0xFFE8ECE8),
    textSecondary: Color(0xFFA3B3A3),
    textHint: Color(0xFF6D7D6D),
    divider: Color(0xFF2C342C),
    error: Color(0xFFE8836B),
    warning: Color(0xFFDDA94E),
    link: Color(0xFF7FB3D9),
    success: Color(0xFF6FBF85),
    accentSubtle: Color(0x389CC49C),
    primarySubtle: Color(0x1F9CC49C),
    linkSubtle: Color(0x1F7FB3D9),
    accentImageSubtle: Color(0x1F9CC49C),
    successSubtle: Color(0x2E6FBF85),
  );

  @override
  AppPalette copyWith({
    Brightness? brightness,
    Color? primary,
    Color? onPrimary,
    Color? accent,
    Color? background,
    Color? surface,
    Color? card,
    Color? textPrimary,
    Color? textSecondary,
    Color? textHint,
    Color? divider,
    Color? error,
    Color? warning,
    Color? link,
    Color? success,
    Color? accentSubtle,
    Color? primarySubtle,
    Color? linkSubtle,
    Color? accentImageSubtle,
    Color? successSubtle,
  }) {
    return AppPalette(
      brightness: brightness ?? this.brightness,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      accent: accent ?? this.accent,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      card: card ?? this.card,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textHint: textHint ?? this.textHint,
      divider: divider ?? this.divider,
      error: error ?? this.error,
      warning: warning ?? this.warning,
      link: link ?? this.link,
      success: success ?? this.success,
      accentSubtle: accentSubtle ?? this.accentSubtle,
      primarySubtle: primarySubtle ?? this.primarySubtle,
      linkSubtle: linkSubtle ?? this.linkSubtle,
      accentImageSubtle: accentImageSubtle ?? this.accentImageSubtle,
      successSubtle: successSubtle ?? this.successSubtle,
    );
  }

  /// Blends two palettes, so changing theme fades rather than snapping.
  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;

    return AppPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      primary: mix(primary, other.primary),
      onPrimary: mix(onPrimary, other.onPrimary),
      accent: mix(accent, other.accent),
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      card: mix(card, other.card),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textHint: mix(textHint, other.textHint),
      divider: mix(divider, other.divider),
      error: mix(error, other.error),
      warning: mix(warning, other.warning),
      link: mix(link, other.link),
      success: mix(success, other.success),
      accentSubtle: mix(accentSubtle, other.accentSubtle),
      primarySubtle: mix(primarySubtle, other.primarySubtle),
      linkSubtle: mix(linkSubtle, other.linkSubtle),
      accentImageSubtle: mix(accentImageSubtle, other.accentImageSubtle),
      successSubtle: mix(successSubtle, other.successSubtle),
    );
  }
}

/// `context.colors.textPrimary` — how widgets should reach a colour.
extension AppPaletteContext on BuildContext {
  AppPalette get colors =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}

/// Colours that stay the same whatever the theme.
abstract class AppColors {
  /// Literal white, for surfaces that are dark in both themes — the image
  /// viewer — and for the QR code, which has to stay black on white to scan.
  static const Color white = Color(0xFFFFFFFF);

  /// Literal black, for the same reason.
  static const Color black = Color(0xFF000000);
}
