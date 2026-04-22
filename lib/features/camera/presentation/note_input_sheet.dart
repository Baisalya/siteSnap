import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/location_service.dart';

import '../../overlay/domain/WatermarkPosition.dart';
import '../../overlay/presentation/saved_notes_provider.dart';
import '../../overlay/presentation/overlay_preview_state.dart';
import 'camera_settings_provider.dart';

class NoteInputSheet extends ConsumerStatefulWidget {
  const NoteInputSheet({super.key});

  @override
  ConsumerState<NoteInputSheet> createState() => _NoteInputSheetState();
}

class _NoteInputSheetState extends ConsumerState<NoteInputSheet> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(savedNotesProvider);

    // ✅ Correct logic
    final recent = notes.take(3).toList(); // view only
    final allNotes = notes;                // full list

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ───── Drag Handle ─────
            const Center(
              child: SizedBox(
                width: 40,
                height: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.grey,
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              "Watermark Position",
              style: TextStyle(color: Colors.grey),
            ),

            Row(
              children: [
                Expanded(
                  child: RadioListTile<WatermarkPosition>(
                    value: WatermarkPosition.bottomLeft,
                    groupValue:
                    ref.watch(overlayPreviewProvider).position,
                    title: const Text("Left",
                        style: TextStyle(color: Colors.white, fontSize: 14)),
                    contentPadding: EdgeInsets.zero,
                    onChanged: (value) {
                      final overlay =
                      ref.read(overlayPreviewProvider);
                      ref.read(overlayPreviewProvider.notifier).state =
                          overlay.copyWith(position: value);
                    },
                  ),
                ),
                Expanded(
                  child: RadioListTile<WatermarkPosition>(
                    value: WatermarkPosition.bottomRight,
                    groupValue:
                    ref.watch(overlayPreviewProvider).position,
                    title: const Text("Right",
                        style: TextStyle(color: Colors.white, fontSize: 14)),
                    contentPadding: EdgeInsets.zero,
                    onChanged: (value) {
                      final overlay =
                      ref.read(overlayPreviewProvider);
                      ref.read(overlayPreviewProvider.notifier).state =
                          overlay.copyWith(position: value);
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // ───── AUTO FETCH TOGGLE ─────
            SwitchListTile(
              title: const Text(
                "Auto-fetch location name",
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              subtitle: const Text(
                "Automatically update note as you move",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              value: ref.watch(cameraSettingsProvider).autoFetchLocation,
              activeColor: Colors.blueAccent,
              contentPadding: EdgeInsets.zero,
              onChanged: (value) {
                ref.read(cameraSettingsProvider.notifier).setAutoFetchLocation(value);
              },
            ),

            const SizedBox(height: 16),

            // ───── INPUT ─────
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: 'Type watermark text or fetch address',
                hintStyle: const TextStyle(color: Colors.grey),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.my_location, color: Colors.blueAccent),
                  tooltip: "Fetch address from GPS",
                  onPressed: () async {
                    final overlay = ref.read(overlayPreviewProvider);
                    final lat = overlay.latitude;
                    final lng = overlay.longitude;

                    if (lat == 0.0 && lng == 0.0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Location not available yet. Please wait for GPS fix."),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }

                    // Show loading
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => const Center(child: CircularProgressIndicator()),
                    );

                    final name = await LocationService.getLocationName(lat, lng);

                    if (context.mounted) {
                      Navigator.pop(context); // hide loading
                      if (name != null) {
                        controller.text = name;
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Could not fetch location name")),
                        );
                      }
                    }
                  },
                ),
              ),
              onSubmitted: (text) async {
                final value = text.trim();
                if (value.isEmpty) return;

                await ref.read(savedNotesProvider.notifier).addNote(value);

                final overlay = ref.read(overlayPreviewProvider);
                ref.read(overlayPreviewProvider.notifier).state =
                    overlay.copyWith(note: value);

                Navigator.pop(context);
              },
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4, left: 4),
              child: Text(
                "Tip: Tap the blue GPS icon to fetch your current address",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),

            const SizedBox(height: 20),

            // ───── RECENT NOTES ─────
            if (recent.isNotEmpty) ...[
              const Text(
                'Recently used',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 8),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: recent.map((note) {
                  return ActionChip(
                    backgroundColor: Colors.white,
                    label: Text(
                      note.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () {
                      ref
                          .read(savedNotesProvider.notifier)
                          .markAsUsed(note);

                      final overlay =
                      ref.read(overlayPreviewProvider);
                      ref
                          .read(overlayPreviewProvider.notifier)
                          .state =
                          overlay.copyWith(note: note.text);

                      Navigator.pop(context);
                    },
                  );
                }).toList(),
              ),

              const SizedBox(height: 20),
            ],

            // ───── ALL NOTES ─────
            if (allNotes.isNotEmpty) ...[
              const Text(
                'All notes',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 8),

              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: allNotes.length,
                separatorBuilder: (_, __) =>
                const Divider(color: Colors.grey),
                itemBuilder: (_, i) {
                  final note = allNotes[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      note.text,
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () {
                      ref
                          .read(savedNotesProvider.notifier)
                          .markAsUsed(note);

                      final overlay =
                      ref.read(overlayPreviewProvider);
                      ref
                          .read(overlayPreviewProvider.notifier)
                          .state =
                          overlay.copyWith(note: note.text);

                      Navigator.pop(context);
                    },
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.delete,
                        color: Colors.red,
                      ),
                      onPressed: () {
                        ref
                            .read(savedNotesProvider.notifier)
                            .deleteNote(note.id);
                      },
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );

  }
}
