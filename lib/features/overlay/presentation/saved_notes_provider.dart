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
    state = await _storage.loadNotes();
  }

  Future<void> addNote(String text) async {
    final note = SavedNote(id: _uuid.v4(), text: text);
    state = [note, ...state];
    await _storage.saveNotes(state);
  }

  Future<void> deleteNote(String id) async {
    state = state.where((n) => n.id != id).toList();
    await _storage.saveNotes(state);
  }
}
