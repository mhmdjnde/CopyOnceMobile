import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controllers/auth_controller.dart';
import 'navigation/auth_gate.dart';
import 'repositories/auth_repository.dart';
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

    return ChangeNotifierProvider(
      create: (_) => AuthController(AuthRepository()),
      child: MaterialApp(
        title: 'CopyOnce',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const AuthGate(),
      ),
    );
  }
}
