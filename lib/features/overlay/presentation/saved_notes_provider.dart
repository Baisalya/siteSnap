import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';
import 'package:surveycam/features/overlay/data/note_storage.dart';
import 'package:surveycam/features/overlay/domain/saved_note.dart';

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

    final normalized = _dedupeAndNormalize(notes);
    state = normalized;
    if (_notesChanged(notes, normalized)) {
      await _storage.saveNotes(normalized);
    }
  }

  Future<void> addNote(String text) async {
    final normalizedText = _historyExtraNoteText(text);
    if (normalizedText.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    // Remove duplicate text
    final filtered = state
        .where((n) => _historyExtraNoteText(n.text) != normalizedText)
        .toList();

    final note = SavedNote(
      id: _uuid.v4(),
      text: normalizedText,
      lastUsedAt: now,
    );

    state = [note, ...filtered];
    await _storage.saveNotes(state);
  }

  Future<void> markAsUsed(SavedNote note) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final normalizedText = _historyExtraNoteText(note.text);

    state = [
      note.copyWith(text: normalizedText, lastUsedAt: now),
      ...state.where((n) => n.id != note.id),
    ];

    await _storage.saveNotes(state);
  }

  Future<void> deleteNote(String id) async {
    state = state.where((n) => n.id != id).toList();
    await _storage.saveNotes(state);
  }

  List<SavedNote> _dedupeAndNormalize(List<SavedNote> notes) {
    final seen = <String>{};
    final normalized = <SavedNote>[];

    for (final note in notes) {
      final text = _historyExtraNoteText(note.text);
      if (text.isEmpty || !seen.add(text)) continue;
      normalized.add(note.copyWith(text: text));
    }

    return normalized;
  }

  bool _notesChanged(List<SavedNote> before, List<SavedNote> after) {
    if (before.length != after.length) return true;
    for (var i = 0; i < before.length; i++) {
      if (before[i].id != after[i].id ||
          before[i].text != after[i].text ||
          before[i].lastUsedAt != after[i].lastUsedAt) {
        return true;
      }
    }
    return false;
  }

  String _historyExtraNoteText(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return '';

    final lines = normalized.split(RegExp(r'\r?\n'));
    if (lines.length <= 1) return normalized;

    return lines.skip(1).join('\n').trim();
  }
}
