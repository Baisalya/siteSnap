import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class WatermarkSupportDialog extends StatelessWidget {
  const WatermarkSupportDialog({super.key});

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);

    if (!await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    )) {
      debugPrint("Could not launch $url");
    }
  }

  Future<void> _openUPI() async {
    final Uri upiUri = Uri.parse(
      "upi://pay?pa=baishalya1999@oksbi&pn=survaycam&cu=INR",
    );

    if (!await launchUrl(
      upiUri,
      mode: LaunchMode.externalApplication,
    )) {
      debugPrint("UPI app not found");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                shape: BoxShape.circle,
              ),
              child: const Text(
                "☕",
                style: TextStyle(fontSize: 40),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "Support SiteSnap!",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "Removing the watermark helps more people find this app. Since it's free, a small coffee ☕ would really help me keep improving it for you! ❤️",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.black87,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _openLink("https://buymeacoffee.com/baisalya");
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.coffee),
                    label: const Text(
                      "Buy me a Coffee",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _openUPI();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.account_balance_wallet_rounded),
                    label: const Text(
                      "Support via UPI",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Maybe Later",
                    style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
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
