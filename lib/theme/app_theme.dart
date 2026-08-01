import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Spacing scale (dp).
abstract class AppSpacing {
  static const double xs = 4.0;
  static const double s = 8.0;
  static const double m = 16.0;
  static const double l = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
}

/// Border-radius scale (dp).
abstract class AppRadius {
  static const double s = 8.0;
  static const double m = 12.0;
  static const double l = 16.0;
  static const double xl = 24.0;
  static const double full = 100.0;
}

abstract class AppTheme {
  /// The light theme, used when the system asks for it.
  static ThemeData get light => _build(AppPalette.light);

  /// The dark theme. Same structure, same spacing, different palette — nothing
  /// about the layout changes between them.
  static ThemeData get dark => _build(AppPalette.dark);

  /// Builds a theme from [c].
  ///
  /// Both themes come through here so a change to shape, spacing, or typography
  /// cannot land in one and be forgotten in the other.
  static ThemeData _build(AppPalette c) {
    final colorScheme = ColorScheme(
      brightness: c.brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      primaryContainer: c.accentSubtle,
      onPrimaryContainer: c.textPrimary,
      secondary: c.accent,
      onSecondary: c.onPrimary,
      secondaryContainer: c.accentSubtle,
      onSecondaryContainer: c.textPrimary,
      surface: c.surface,
      onSurface: c.textPrimary,
      error: c.error,
      onError: c.onPrimary,
      outline: c.divider,
      outlineVariant: c.divider,
    );

    return ThemeData(
      useMaterial3: true,
      extensions: [c],
      brightness: c.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: c.background,
      // Cards
      cardTheme: CardThemeData(
        color: c.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.l),
          side: BorderSide(color: c.divider),
        ),
        margin: EdgeInsets.zero,
      ),
      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: c.textPrimary,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: c.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      // Bottom NavigationBar (Material 3)
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: c.accentSubtle,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? c.primary : c.textHint,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? c.primary : c.textHint,
            size: 22,
          );
        }),
      ),
      // NavigationRail (wide layout)
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.card,
        selectedIconTheme: IconThemeData(color: c.primary, size: 22),
        unselectedIconTheme: IconThemeData(color: c.textHint, size: 22),
        selectedLabelTextStyle: TextStyle(
          color: c.primary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(color: c.textHint, fontSize: 12),
        indicatorColor: c.accentSubtle,
        useIndicator: true,
      ),
      // Inputs
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.l),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.l),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.l),
          borderSide: BorderSide(color: c.accent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.m,
          vertical: AppSpacing.m,
        ),
        hintStyle: TextStyle(color: c.textHint, fontSize: 15),
        prefixIconColor: c.textHint,
      ),
      // Filter chips
      chipTheme: ChipThemeData(
        backgroundColor: c.surface,
        selectedColor: c.primary,
        disabledColor: c.surface,
        labelStyle: TextStyle(
          color: c.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        secondaryLabelStyle: TextStyle(
          color: c.onPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.m,
          vertical: AppSpacing.xs,
        ),
      ),
      // Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.m,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.l),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: c.primary),
      ),
      // Dividers
      dividerTheme: DividerThemeData(color: c.divider, thickness: 1, space: 0),
      // ListTile defaults
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.m,
          vertical: AppSpacing.xs,
        ),
        minLeadingWidth: 0,
      ),
    );
  }
}
