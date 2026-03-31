import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:survaycam/features/camera/presentation/camera_screen.dart';
import 'package:survaycam/privacypolicy/PrivacyDialog.dart';
import 'package:survaycam/privacypolicy/privacyProvider.dart';

class RootScreen extends ConsumerWidget {
  const RootScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(privacyProvider);

    // ⏳ LOADING
    if (status == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 🚨 NOT ACCEPTED → show dialog ONCE
    if (status == false) {
      Future.microtask(() {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const PrivacyDialog(),
        );
      });
    }

    // ✅ MAIN APP
    return const CameraScreen();
  }
}