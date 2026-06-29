import 'package:flutter_test/flutter_test.dart';

// Helper functions copied from NoteInputSheet for testing logic
String _locationLineFromWatermark(String value) {
  if (value.isEmpty) return '';
  final lines = value.split(RegExp(r'\r?\n'));
  return lines.isEmpty ? '' : lines.first.trim();
}

String _extraNoteFromWatermark(String value) {
  final lines = value.split(RegExp(r'\r?\n'));
  if (lines.length <= 1) return '';
  return lines.skip(1).join('\n').trim();
}

String _composeWatermarkText(String location, String extraNote) {
  final loc = location.trim();
  final extra = extraNote.trim();

  if (extra.isEmpty) return loc;
  return "$loc\n$extra";
}

void main() {
  group('Note Composition Logic', () {
    test('composes note with empty Line 1', () {
      final result = _composeWatermarkText('', 'Extra Note');
      expect(result, '\nExtra Note');
    });

    test('composes note with both lines', () {
      final result = _composeWatermarkText('Location', 'Extra Note');
      expect(result, 'Location\nExtra Note');
    });

    test('extracts Line 1 when Line 1 is empty', () {
      final input = '\nExtra Note';
      expect(_locationLineFromWatermark(input), '');
    });

    test('extracts Line 2 when Line 1 is empty', () {
      final input = '\nExtra Note';
      expect(_extraNoteFromWatermark(input), 'Extra Note');
    });

    test('extracts Line 1 when both exist', () {
      final input = 'Location\nExtra Note';
      expect(_locationLineFromWatermark(input), 'Location');
    });

    test('extracts Line 2 when both exist', () {
      final input = 'Location\nExtra Note';
      expect(_extraNoteFromWatermark(input), 'Extra Note');
    });
  });
}
