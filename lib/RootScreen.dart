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
  String _unauthorizedTitle = "";
  String _unauthorizedMessage = "";
  String _unauthorizedSolution = "";

  @override
  void initState() {
    super.initState();
    _performSecurityCheck();
  }

  Future<void> _performSecurityCheck() async {
    if (!Platform.isAndroid) return;

    try {
      // This detects if the app is running in Release Mode (v/s Debug/Profile mode)
      const bool isRelease = bool.fromEnvironment('dart.vm.product');

      // 1. Check if it's a real device (Skip if not in Release mode)
      bool isRealDevice = await SafeDevice.isRealDevice;
      if (isRelease && !isRealDevice) {
        _flagUnauthorized(
          title: "Emulator Detected",
          message: "This app is designed to run only on physical devices to ensure data security.",
          solution: "Please install the app on a real Android smartphone.",
        );
        return;
      }

      // 2. Check for Root/Jailbreak
      bool isJailBroken = await SafeDevice.isJailBroken;
      if (isJailBroken) {
        _flagUnauthorized(
          title: "Security Risk: Rooted Device",
          message: "Your device appears to be rooted. This compromises the security of your data.",
          solution: "To continue, use a non-rooted device or hide root access using tools like Magisk (DenyList).",
        );
        return;
      }

      // 3. Check for Developer Options (Bypass in Debug mode so you can run from Android Studio)
      bool isDevMode = await SafeDevice.isDevelopmentModeEnable;
      if (isRelease && isDevMode) {
        _flagUnauthorized(
          title: "Developer Options Enabled",
          message: "Developer Options or USB Debugging is enabled, which is a security risk.",
          solution: "Go to Settings > System > Developer Options and turn it OFF. Then restart the app.",
        );
        return;
      }

      // 4. Check for Mock Location
      bool isMockLocation = await SafeDevice.isMockLocation;
      if (isMockLocation) {
        _flagUnauthorized(
          title: "Mock Location Detected",
          message: "The app has detected that Mock Locations are enabled.",
          solution: "Please disable any spoofing apps and turn off 'Select mock location app' in Developer Options.",
        );
        return;
      }

      // 5. Verify Installer (Only in Release mode)
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String? installer = packageInfo.installerStore;

      if (isRelease && (installer == null || !installer.contains('vending'))) {
        _flagUnauthorized(
          title: "Unauthorized Version",
          message: "This app was not installed from the official Google Play Store.",
          solution: "Please uninstall this app and download the original version from the Play Store.",
        );
        return;
      }

      // All checks passed
      setState(() {
        _isUnauthorized = false;
      });
      _checkForUpdate();
    } catch (e) {
      debugPrint('Security check error: $e');
    }
  }

  void _flagUnauthorized({required String title, required String message, required String solution}) {
    setState(() {
      _isUnauthorized = true;
      _unauthorizedTitle = title;
      _unauthorizedMessage = message;
      _unauthorizedSolution = solution;
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
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.security_rounded, color: Colors.redAccent, size: 100),
                const SizedBox(height: 30),
                Text(
                  _unauthorizedTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _unauthorizedMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[300], fontSize: 16),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.lightbulb_outline, color: Colors.amber, size: 20),
                          SizedBox(width: 8),
                          Text(
                            "How to fix this:",
                            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _unauthorizedSolution,
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _performSecurityCheck(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text(
                          "Check Again",
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => SystemNavigator.pop(),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.redAccent),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text(
                          "Exit Application",
                          style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                )
              ],
            ),
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