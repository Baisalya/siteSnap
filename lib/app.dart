import 'package:flutter/material.dart';
import 'package:survaycam/RootScreen.dart';
import 'package:survaycam/privacypolicy/SplashScreen.dart';
import 'core/theme/app_theme.dart';
import 'features/camera/presentation/camera_screen.dart';

class SurveyCamApp extends StatelessWidget {
  const SurveyCamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SurveyCam',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const AppLauncher(),
    );
  }
}
