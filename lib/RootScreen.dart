import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:safe_device/safe_device.dart';

import 'package:surveycam/privacypolicy/SplashScreen.dart';
import 'package:surveycam/privacypolicy/privacyProvider.dart';

import 'features/camera/presentation/camera_screen.dart';

class AppLauncher extends ConsumerStatefulWidget {
  const AppLauncher({super.key});

  @override
  ConsumerState<AppLauncher> createState() => _AppLauncherState();
}

class _AppLauncherState extends ConsumerState<AppLauncher> {
  bool _isUnauthorized = false;
  String _unauthorizedMessage = "";

  @override
  void initState() {
    super.initState();
    _performSecurityCheck();
  }

  Future<void> _performSecurityCheck() async {
    if (!Platform.isAndroid) return;

    try {
      // 1. Check if device is safe (not rooted, not an emulator)
      bool isRealDevice = await SafeDevice.isRealDevice;
      bool isJailBroken = await SafeDevice.isJailBroken;

      if (!isRealDevice || isJailBroken) {
        _flagUnauthorized("Security Alert: This app cannot run on rooted devices or emulators for security reasons.");
        return;
      }

      // 2. Verify Installer (Was it downloaded from Play Store?)
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String? installer = packageInfo.installerStore;

      // In Debug mode, installer is null. 
      // In Release mode, it should be 'com.android.vending' for Play Store.
      const bool isRelease = bool.fromEnvironment('dart.vm.product');
      if (isRelease && (installer == null || !installer.contains('vending'))) {
        _flagUnauthorized("Unauthorized Version: This app was not installed from the official Google Play Store. Please download the original app.");
        return;
      }

      // 3. Check for Updates
      _checkForUpdate();
    } catch (e) {
      debugPrint('Security check error: $e');
    }
  }

  void _flagUnauthorized(String message) {
    setState(() {
      _isUnauthorized = true;
      _unauthorizedMessage = message;
    });
  }

  Future<void> _checkForUpdate() async {
    try {
      final updateInfo = await InAppUpdate.checkForUpdate();
      if (updateInfo.updateAvailability == UpdateAvailability.updateAvailable) {
        await InAppUpdate.performImmediateUpdate();
      }
    } catch (e) {
      debugPrint('Update check error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isUnauthorized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security_update_warning, color: Colors.red, size: 80),
              const SizedBox(height: 20),
              Text(
                _unauthorizedMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () => SystemNavigator.pop(),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text("Exit App", style: TextStyle(color: Colors.white)),
              )
            ],
          ),
        ),
      );
    }

    final status = ref.watch(privacyProvider);

    if (status == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: SizedBox.shrink()),
      );
    }

    if (status == false) {
      return const SplashScreen();
    }

    return const CameraScreen();
  }
}