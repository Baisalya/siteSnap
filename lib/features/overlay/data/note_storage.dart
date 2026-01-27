import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/saved_note.dart';

class NoteStorage {
  static const _key = 'saved_watermark_notes';

  Future<List<SavedNote>> loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];

    return raw
        .map((e) => SavedNote.fromJson(jsonDecode(e)))
        .toList();
  }

  Future<void> saveNotes(List<SavedNote> notes) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded =
    notes.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_key, encoded);
  }
}
