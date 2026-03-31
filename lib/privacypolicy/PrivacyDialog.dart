import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:survaycam/privacypolicy/privacyProvider.dart';

class PrivacyDialog extends ConsumerWidget {
  const PrivacyDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.privacy_tip, size: 32, color: Colors.blue),
            const SizedBox(height: 10),

            const Text(
              "Privacy Policy",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            // 🔥 FULL POLICY SCROLL
            SizedBox(
              height: 350,
              child: SingleChildScrollView(
                child: Text(
                  """
Effective Date: [30/03/26]

SurveyCam respects your privacy and is committed to protecting it.

1. Information We Collect
SurveyCam does NOT collect or store personal data on any server.

However, the app may access:
• Camera – to capture photos
• Location (GPS) – to embed latitude, longitude, and address
• Storage – to save images locally on your device

2. How We Use Information
Used only for:
• Capturing photos
• Adding location, date, and time overlays
• Providing proof-based documentation

We DO NOT use data for advertising, tracking, or analytics.

3. Data Sharing
We do NOT share, sell, or transfer your data.
All data remains on your device unless you share it manually.

4. Data Security
We do not store any user data externally.
Everything stays on your device.

5. Permissions
• Camera – capture photos
• Location – geo-tagging
• Storage – save images

6. Third-Party Services
No third-party services are used.

7. Children's Privacy
Not intended for children under 13.

8. Your Control
• You can deny permissions anytime
• You can delete stored images anytime

9. Changes
Policy may be updated in future.

10. Contact
Email: baishalya1999@gmail.com

By tapping ACCEPT, you agree to this Privacy Policy.
                  """,
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
            ),

            const SizedBox(height: 15),

            // 🔘 Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("DECLINE"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      ref.read(privacyProvider.notifier).acceptPolicy();
                      Navigator.pop(context);
                    },
                    child: const Text("ACCEPT"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}