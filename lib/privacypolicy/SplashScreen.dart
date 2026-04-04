import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:surveycam/privacypolicy/privacyProvider.dart';

import '../features/camera/presentation/camera_screen.dart';
import 'PrivacyDialog.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(privacyProvider);

    /// 🔥 MAIN FIX: Run AFTER UI build
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_handled) return;
      if (!mounted) return;

      /// ⏳ Still loading → wait
      if (status == null) return;

      _handled = true;

      /// ❌ Not accepted → show dialog
      if (status == false) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const PrivacyDialog(),
        );
      }

      /// ✅ Navigate after dialog OR if already accepted
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const CameraScreen(),
        ),
      );
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [

          /// 📷 BACKGROUND
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black,
                  Colors.grey.shade900,
                  Colors.black,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          /// 🧭 TOP BAR
          Positioned(
            top: 40,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Icon(Icons.flash_off, color: Colors.white70),
                Icon(Icons.hdr_auto, color: Colors.white70),
                Icon(Icons.settings, color: Colors.white70),
              ],
            ),
          ),

          /// 🎯 FOCUS FRAME
          Center(
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white54, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          /// ✨ APP NAME
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.camera_alt, color: Colors.white, size: 40),
                SizedBox(height: 10),
                Text(
                  "SurveyCam",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  "Geo Tagged Camera",
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          /// 🔘 BOTTOM UI
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Column(
              children: [

                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  child: Center(
                    child: Container(
                      width: 55,
                      height: 55,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 15),

                const Text(
                  "PHOTO",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 20),

                /// ⏳ Loading
                if (status == null)
                  const CircularProgressIndicator(color: Colors.white),
              ],
            ),
          ),
        ],
      ),
    );
  }
}