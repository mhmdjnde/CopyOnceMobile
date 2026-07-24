import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

class CopyOnceApp extends StatelessWidget {
  const CopyOnceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CopyOnce',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const SplashScreen(),
    );
  }
}
