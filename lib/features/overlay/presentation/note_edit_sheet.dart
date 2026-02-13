import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/WatermarkPosition.dart';
import 'note_controller.dart';
import 'overlay_preview_state.dart';


class NoteEditSheet extends ConsumerWidget {
  const NoteEditSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final note = ref.watch(noteControllerProvider);
    final overlay = ref.watch(overlayPreviewProvider);

    return Padding(
      padding: MediaQuery.of(context).viewInsets,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Edit Watermark Text',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            // ===========================
            // NOTE TEXT FIELD
            // ===========================
            TextField(
              maxLength: 120,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Project / Site / Notes',
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: note)
                ..selection = TextSelection.fromPosition(
                  TextPosition(offset: note.length),
                ),
              onChanged: (value) {
                ref
                    .read(noteControllerProvider.notifier)
                    .update(value);
              },
            ),

            const SizedBox(height: 10),

            // ===========================
            // POSITION SWITCH
            // ===========================
            Row(
              mainAxisAlignment:
              MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Left Overlay Position",
                  style: TextStyle(fontSize: 16),
                ),
                Switch(
                  value: overlay.position ==
                      WatermarkPosition.bottomLeft,
                  onChanged: (value) {
                    ref
                        .read(overlayPreviewProvider.notifier)
                        .state = overlay.copyWith(
                      position: value
                          ? WatermarkPosition.bottomLeft
                          : WatermarkPosition.bottomRight,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
