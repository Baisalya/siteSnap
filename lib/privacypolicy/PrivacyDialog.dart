import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitesnap/privacypolicy/privacyProvider.dart';

class PrivacyDialog extends ConsumerWidget {
  const PrivacyDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: const Text("Privacy Policy"),
      content: const SingleChildScrollView(
        child: Text(
          "SurveyCam respects your privacy.\n\n"
              "We do not collect or store personal data.\n"
              "Camera and storage permissions are used only for app functionality.\n\n"
              "By tapping ACCEPT, you agree to our Privacy Policy.",
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () {
            ref.read(privacyProvider.notifier).acceptPolicy();
            Navigator.pop(context);
          },
          child: const Text("ACCEPT"),
        ),
      ],
    );
  }
}