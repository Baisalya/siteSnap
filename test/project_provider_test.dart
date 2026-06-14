import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surveycam/features/projects/presentation/project_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('active project assigns and filters gallery files', () async {
    final controller = ProjectController();
    addTearDown(controller.dispose);

    await Future<void>.delayed(Duration.zero);

    await controller.createProject('Site A');

    final projectFile = File('C:/captures/site-a.jpg');
    final otherFile = File('C:/captures/other.jpg');

    await controller.assignFileToActiveProject(projectFile);

    expect(
      controller.filterFilesForActiveProject([projectFile, otherFile]),
      [projectFile],
    );

    await controller.setActiveProject(null);

    expect(
      controller.filterFilesForActiveProject([projectFile, otherFile]),
      [projectFile, otherFile],
    );
  });
}
