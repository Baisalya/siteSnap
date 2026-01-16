import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../overlay/presentation/overlay_preview_state.dart';

class NoteInputSheet extends ConsumerStatefulWidget {
  const NoteInputSheet({super.key});

  @override
  ConsumerState<NoteInputSheet> createState() => _NoteInputSheetState();
}

class _NoteInputSheetState extends ConsumerState<NoteInputSheet> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(overlayPreviewProvider).note,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        top: 16,
      ),
      child: Material(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // HEADER
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Edit Watermark Text',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.check),
                  onPressed: () {
                    // ✅ SAVE TEXT
                    ref.read(overlayPreviewProvider.notifier).state =
                        ref.read(overlayPreviewProvider).copyWith(
                          note: _controller.text.trim(),
                        );

                    // ✅ AUTO CLOSE SHEET
                    Navigator.pop(context);
                  },
                ),
              ],
            ),

            const SizedBox(height: 12),

            // TEXT FIELD
            TextField(
              controller: _controller,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Enter watermark note...',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
