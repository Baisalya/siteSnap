import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'overlay_preview_state.dart';

final noteControllerProvider =
StateNotifierProvider<NoteController, String>((ref) {
  return NoteController(ref);
});

class NoteController extends StateNotifier<String> {
  final Ref ref;

  NoteController(this.ref) : super('');

  void update(String value) {
    state = value;

    final overlay = ref.read(overlayPreviewProvider);
    ref.read(overlayPreviewProvider.notifier).state =
        overlay.copyWith(note: value);
  }
}
