import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controllers/auth_controller.dart';
import 'controllers/clipboard_controller.dart';
import 'controllers/settings_controller.dart';
import 'navigation/auth_gate.dart';
import 'repositories/auth_repository.dart';
import 'repositories/clipboard_repository.dart';
import 'repositories/settings_repository.dart';
import 'screens/config_error_screen.dart';
import 'theme/app_theme.dart';

class CopyOnceApp extends StatelessWidget {
  const CopyOnceApp({super.key, this.configError});

  /// Set when the app was launched without Supabase credentials; the app then
  /// shows setup instructions instead of a broken sign-in screen.
  final String? configError;

  @override
  Widget build(BuildContext context) {
    if (configError != null) {
      return MaterialApp(
        title: 'CopyOnce',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: ConfigErrorScreen(message: configError!),
      );
    }

    // The repository is provided rather than constructed inline so the security
    // screens can build their own controller against the same instance.
    return MultiProvider(
      providers: [
        Provider<AuthRepository>(create: (_) => AuthRepository()),
        Provider<ClipboardRepository>(create: (_) => ClipboardRepository()),
        Provider<SettingsRepository>(create: (_) => SettingsRepository()),
        ChangeNotifierProvider(
          create: (context) => AuthController(context.read<AuthRepository>()),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              SettingsController(context.read<SettingsRepository>()),
        ),
        // Depends on settings for the filter and Wi-Fi rules, so it is declared
        // after them. Neither loads anything until the app is past the gate.
        ChangeNotifierProvider(
          create: (context) => ClipboardController(
            context.read<ClipboardRepository>(),
            context.read<SettingsController>(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'CopyOnce',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const AuthGate(),
      ),
    );
  }
}
