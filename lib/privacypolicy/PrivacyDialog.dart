import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:surveycam/privacypolicy/privacyProvider.dart';

class PrivacyDialog extends ConsumerWidget {
  const PrivacyDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      elevation: 8,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            /// 🔐 ICON + TITLE
            Row(
              children: const [
                Icon(Icons.privacy_tip_rounded,
                    size: 30, color: Colors.blue),
                SizedBox(width: 10),
                Text(
                  "Privacy Policy",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            /// 📜 CONTENT
            SizedBox(
              height: 380,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _SectionTitle("Effective Date"),
                    _BodyText("30 March 2026"),

                    SizedBox(height: 12),

                    _SectionTitle("Overview"),
                    _BodyText(
                        "SurveyCam respects your privacy and is committed to protecting your personal data. This app is designed to function without collecting or storing user data externally."),

                    SizedBox(height: 12),

                    _SectionTitle("1. Information We Access"),
                    _Bullet("Camera – Capture photos"),
                    _Bullet("Location (GPS) – Add geo-tagging"),
                    _Bullet("Storage – Save images locally"),

                    SizedBox(height: 12),

                    _SectionTitle("2. How We Use Information"),
                    _Bullet("Capture and store images"),
                    _Bullet("Embed date, time, and location"),
                    _Bullet("Provide proof-based documentation"),

                    _BodyText(
                        "We do NOT use your data for advertising, tracking, or analytics."),

                    SizedBox(height: 12),

                    _SectionTitle("3. Data Sharing"),
                    _BodyText(
                        "We do NOT share, sell, or transfer your data. All data remains on your device unless you choose to share it."),

                    SizedBox(height: 12),

                    _SectionTitle("4. Data Security"),
                    _BodyText(
                        "We do not store any data on external servers. Your data stays securely on your device."),

                    SizedBox(height: 12),

                    _SectionTitle("5. Permissions"),
                    _Bullet("Camera access"),
                    _Bullet("Location access"),
                    _Bullet("Storage access"),

                    SizedBox(height: 12),

                    _SectionTitle("6. Third-Party Services"),
                    _BodyText("No third-party services are used."),

                    SizedBox(height: 12),

                    _SectionTitle("7. Children's Privacy"),
                    _BodyText(
                        "This app is not intended for children under 13 years of age."),

                    SizedBox(height: 12),

                    _SectionTitle("8. Your Control"),
                    _Bullet("You can deny permissions anytime"),
                    _Bullet("You can delete stored data anytime"),

                    SizedBox(height: 12),

                    _SectionTitle("9. Changes"),
                    _BodyText(
                        "We may update this Privacy Policy in the future."),

                    SizedBox(height: 12),

                    _SectionTitle("10. Contact"),
                    _BodyText("Email: baishalya1999@gmail.com"),

                    SizedBox(height: 16),

                    _BodyText(
                      "By tapping ACCEPT, you agree to this Privacy Policy.",
                      isBold: true,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 18),

            /// 🔘 BUTTONS
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      SystemNavigator.pop();
                    },
                    child: const Text(
                      "DECLINE",
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      backgroundColor: Colors.blue,
                    ),
                    onPressed: () async {
                      await ref
                          .read(privacyProvider.notifier)
                          .acceptPolicy();

                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    },
                    child: const Text(
                      "ACCEPT",
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
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

/// 🔹 Section Title Widget
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// 🔹 Body Text
class _BodyText extends StatelessWidget {
  final String text;
  final bool isBold;
  const _BodyText(this.text, {this.isBold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          height: 1.5,
          fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
          color: Colors.black87,
        ),
      ),
    );
  }
}

/// 🔹 Bullet Point
class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("• ", style: TextStyle(fontSize: 13)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}