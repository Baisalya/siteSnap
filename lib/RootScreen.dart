import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:survaycam/privacypolicy/SplashScreen.dart';
import 'package:survaycam/privacypolicy/privacyProvider.dart';

import 'features/camera/presentation/camera_screen.dart';

class AppLauncher extends ConsumerWidget {
  const AppLauncher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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