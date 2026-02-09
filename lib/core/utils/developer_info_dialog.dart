import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class DeveloperInfoDialog extends StatelessWidget {
  const DeveloperInfoDialog({super.key});

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);

    if (!await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    )) {
      debugPrint("Could not launch $url");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt,
                color: Colors.white, size: 40),

            const SizedBox(height: 12),

            const Text(
              "SiteSnap",
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              "Developed by Baisalya",
              style: TextStyle(color: Colors.grey),
            ),

            const SizedBox(height: 20),

            // PORTFOLIO BUTTON
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  _openLink(
                      "https://baisalya.github.io/Baisalya-Roul/");
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side:
                  const BorderSide(color: Colors.white),
                ),
                child: const Text("View Portfolio"),
              ),
            ),

            const SizedBox(height: 10),

            // BUY ME A COFFEE
            /*SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.coffee),
                label: const Text("Buy me a Coffee"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
                onPressed: () {
                  _openLink(
                      "https://buymeacoffee.com/bAISALYA");
                },
              ),
            ),*/

            const SizedBox(height: 8),

            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "Close",
                style: TextStyle(color: Colors.grey),
              ),
            )
          ],
        ),
      ),
    );
  }
}
