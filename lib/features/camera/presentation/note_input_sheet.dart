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
  Widget build(BuildContext context) {
    final notes = ref.watch(savedNotesProvider);

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ✏️ Input
          TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Enter watermark note',
              hintStyle: TextStyle(color: Colors.grey),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (text) async {
              if (text.trim().isEmpty) return;

              // Save note
              await ref
                  .read(savedNotesProvider.notifier)
                  .addNote(text);

              // Apply to overlay
              final overlay = ref.read(overlayPreviewProvider);
              ref.read(overlayPreviewProvider.notifier).state =
                  overlay.copyWith(note: text);

              Navigator.pop(context); // ✅ auto close
            },
          ),

          const SizedBox(height: 16),

          // 📜 Saved notes list
          if (notes.isNotEmpty)
            ListView.builder(
              shrinkWrap: true,
              itemCount: notes.length,
              itemBuilder: (_, i) {
                final note = notes[i];
                return ListTile(
                  title: Text(
                    note.text,
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    final overlay = ref.read(overlayPreviewProvider);
                    ref.read(overlayPreviewProvider.notifier).state =
                        overlay.copyWith(note: note.text);
                    Navigator.pop(context);
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
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
      ),
    );
  }
}
