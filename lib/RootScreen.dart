import 'dart:io';

import 'package:flutter/foundation.dart'; // ✅ IMPORTANT
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
      const bool isRelease = bool.fromEnvironment('dart.vm.product');

      /// ✅ 1. Emulator check (only in release)
      bool isRealDevice = await SafeDevice.isRealDevice;
      if (isRelease && !isRealDevice) {
        _flagUnauthorized(
          title: "Emulator Detected",
          message: "Run this app on a real device.",
          solution: "Install on a physical Android phone.",
        );
        return;
      }

      /// ✅ 2. Root check
      bool isJailBroken = await SafeDevice.isJailBroken;
      if (isJailBroken) {
        _flagUnauthorized(
          title: "Rooted Device",
          message: "Device security compromised.",
          solution: "Use a non-rooted device.",
        );
        return;
      }

      /// ✅ 3. Dev mode (only in release)
      bool isDevMode = await SafeDevice.isDevelopmentModeEnable;
      if (isRelease && isDevMode) {
        _flagUnauthorized(
          title: "Developer Mode Enabled",
          message: "Disable developer options.",
          solution: "Turn off USB debugging.",
        );
        return;
      }

      /// ✅ 4. Mock location
      bool isMockLocation = await SafeDevice.isMockLocation;
      if (isMockLocation) {
        _flagUnauthorized(
          title: "Mock Location",
          message: "Location spoofing detected.",
          solution: "Disable mock location apps.",
        );
        return;
      }

      /// ✅ 5. Installer check (only in release)
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String? installer = packageInfo.installerStore;

      if (isRelease && (installer == null || !installer.contains('vending'))) {
        _flagUnauthorized(
          title: "Unauthorized App",
          message: "Install from Play Store only.",
          solution: "Download from official source.",
        );
        return;
      }

      /// ✅ ALL GOOD
      setState(() {
        _isUnauthorized = false;
      });

      /// 🔥 Safe update check
      _checkForUpdate();

    } catch (e) {
      debugPrint('Security check error: $e');
    }
  }

  void _flagUnauthorized({
    required String title,
    required String message,
    required String solution,
  }) {
    setState(() {
      _isUnauthorized = true;
      _unauthorizedTitle = title;
      _unauthorizedMessage = message;
      _unauthorizedSolution = solution;
    });
  }

  /// 🔥 FULLY SAFE UPDATE CHECK
  Future<void> _checkForUpdate() async {
    /// ❌ Skip in debug/dev
    if (!kReleaseMode) {
      debugPrint("⛔ Debug mode → skipping in-app update");
      return;
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final installer = packageInfo.installerStore;

      /// ❌ Not Play Store install
      if (installer == null || !installer.contains('vending')) {
        debugPrint("⛔ Not Play Store install → skipping update");
        return;
      }

      final updateInfo = await InAppUpdate.checkForUpdate();

      if (updateInfo.updateAvailability ==
          UpdateAvailability.updateAvailable) {
        await InAppUpdate.performImmediateUpdate();
      }
    } catch (e) {
      debugPrint('Update check safe error: $e');
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
                const Icon(Icons.security_rounded,
                    color: Colors.redAccent, size: 100),
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
                  style:
                  TextStyle(color: Colors.grey[300], fontSize: 16),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.lightbulb_outline,
                              color: Colors.amber, size: 20),
                          SizedBox(width: 8),
                          Text(
                            "How to fix this:",
                            style: TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _unauthorizedSolution,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 14),
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
                        onPressed: _performSecurityCheck,
                        child: const Text("Check Again"),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => SystemNavigator.pop(),
                        child: const Text("Exit Application"),
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