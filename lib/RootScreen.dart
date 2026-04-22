import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';

import 'package:surveycam/privacypolicy/SplashScreen.dart';
import 'package:surveycam/privacypolicy/privacyProvider.dart';

import 'features/camera/presentation/camera_screen.dart';

class AppLauncher extends ConsumerStatefulWidget {
  const AppLauncher({super.key});

  @override
  ConsumerState<AppLauncher> createState() => _AppLauncherState();
}

class _AppLauncherState extends ConsumerState<AppLauncher> {
  @override
  void initState() {
    super.initState();
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    if (Platform.isAndroid) {
      try {
        final updateInfo = await InAppUpdate.checkForUpdate();
        if (updateInfo.updateAvailability == UpdateAvailability.updateAvailable) {
          // You can choose between performImmediateUpdate() or showFlexibleUpdate()
          // Immediate update forces the user to update before using the app
          await InAppUpdate.performImmediateUpdate();
        }
      } catch (e) {
        debugPrint('Error checking for update: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(privacyProvider);

    /// ⏳ Still loading → show NOTHING (or minimal loader)
    if (status == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: SizedBox.shrink(), // 👈 no fake UI flash
        ),
      );
    }

    /// ❌ Not accepted
    if (status == false) {
      return const SplashScreen(); // this shows dialog
    }

    /// ✅ Accepted → DIRECT CAMERA
    return const CameraScreen();
  }
}