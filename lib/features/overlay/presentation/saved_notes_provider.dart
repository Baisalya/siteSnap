import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../data/note_storage.dart';
import '../domain/saved_note.dart';

final savedNotesProvider =
StateNotifierProvider<SavedNotesController, List<SavedNote>>(
      (ref) => SavedNotesController(),
);

class SavedNotesController extends StateNotifier<List<SavedNote>> {
  final _storage = NoteStorage();
  final _uuid = const Uuid();

  SavedNotesController() : super([]) {
    _load();
  }

  Future<void> _load() async {
    final notes = await _storage.loadNotes();

    // Always keep sorted by recent usage
    notes.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));

    state = notes;
  }

  Future<void> addNote(String text) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Remove duplicate text
    final filtered = state.where((n) => n.text != text).toList();

    final note = SavedNote(
      id: _uuid.v4(),
      text: text,
      lastUsedAt: now,
    );

    state = [note, ...filtered];
    await _storage.saveNotes(state);
  }

  Future<void> markAsUsed(SavedNote note) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    state = [
      note.copyWith(lastUsedAt: now),
      ...state.where((n) => n.id != note.id),
    ];

    await _storage.saveNotes(state);
  }

  Future<void> deleteNote(String id) async {
    state = state.where((n) => n.id != id).toList();
    await _storage.saveNotes(state);
  }
}
