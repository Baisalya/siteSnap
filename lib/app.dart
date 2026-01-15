import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'features/camera/presentation/camera_screen.dart';

class NoteCamApp extends StatelessWidget {
  const NoteCamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NoteCam Pro',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const CameraScreen(),
    );
  }
}
