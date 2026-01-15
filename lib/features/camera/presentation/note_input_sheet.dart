import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../overlay/presentation/note_controller.dart';

class NoteInputSheet extends ConsumerWidget {
  const NoteInputSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final note = ref.watch(noteControllerProvider);

    return Padding(
      padding: MediaQuery.of(context).viewInsets,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Add Note',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              maxLength: 120,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Site name, project, remarks...',
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: note)
                ..selection = TextSelection.fromPosition(
                  TextPosition(offset: note.length),
                ),
              onChanged: (value) {
                ref.read(noteControllerProvider.notifier).update(value);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
