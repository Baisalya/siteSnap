import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../overlay/presentation/saved_notes_provider.dart';
import '../../overlay/presentation/overlay_preview_state.dart';

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

          // ───── INPUT ─────
          TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: 'Type new watermark text',
              hintStyle: TextStyle(color: Colors.grey),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (text) async {
              final value = text.trim();
              if (value.isEmpty) return;

              await ref
                  .read(savedNotesProvider.notifier)
                  .addNote(value);

              final overlay = ref.read(overlayPreviewProvider);
              ref.read(overlayPreviewProvider.notifier).state =
                  overlay.copyWith(note: value);

              Navigator.pop(context); // ✅ auto close
            },
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

            SizedBox(
              height: 240,
              child: ListView.separated(
                itemCount: allNotes.length,
                separatorBuilder: (_, __) =>
                const Divider(color: Colors.grey),
                itemBuilder: (_, i) {
                  final note = allNotes[i];
                  return ListTile(
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
            ),
          ],
        ],
      ),
    );
  }
}
