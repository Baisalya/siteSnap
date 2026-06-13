import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surveycam/features/overlay/presentation/saved_notes_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('saved note history stores only line two extra note text', () async {
    final controller = SavedNotesController();
    addTearDown(controller.dispose);

    await Future<void>.delayed(Duration.zero);

    await controller.addNote('Site A\nInspection complete');

    expect(controller.state, hasLength(1));
    expect(controller.state.single.text, 'Inspection complete');
  });

  test('saved note history dedupes by extra note text', () async {
    final controller = SavedNotesController();
    addTearDown(controller.dispose);

    await Future<void>.delayed(Duration.zero);

    await controller.addNote('Site A\nInspection complete');
    await controller.addNote('Site B\nInspection complete');

    expect(controller.state, hasLength(1));
    expect(controller.state.single.text, 'Inspection complete');
  });
}
