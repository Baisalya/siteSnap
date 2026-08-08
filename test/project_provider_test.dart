import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:surveycam/features/gallery/data/sitesnap_gallery_repository.dart';
import 'package:surveycam/features/projects/data/project_storage.dart';
import 'package:surveycam/features/projects/domain/project.dart';
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

  test('per-file assignments survive concurrent writes', () async {
    final storage = ProjectStorage();

    await Future.wait([
      storage.assignFilePath(
        filePath: 'C:/captures/one.jpg',
        projectId: 'project-a',
      ),
      storage.assignFilePath(
        filePath: 'C:/captures/two.jpg',
        projectId: 'project-b',
      ),
    ]);

    final assignments = await storage.loadAssignments();
    expect(
        assignments[ProjectStorage.assignmentKeyForFile(
          File('C:/captures/one.jpg'),
        )],
        'project-a');
    expect(
        assignments[ProjectStorage.assignmentKeyForFile(
          File('C:/captures/two.jpg'),
        )],
        'project-b');
  });

  test('legacy assignment maps migrate without losing project membership',
      () async {
    final file = File('C:/captures/legacy.jpg');
    final key = ProjectStorage.legacyAssignmentKeyForFile(file);
    SharedPreferences.setMockInitialValues({
      'surveycam_project_assignments': jsonEncode({key: 'legacy-project'}),
    });

    final assignments = await ProjectStorage().loadAssignments();

    expect(assignments[key], 'legacy-project');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('surveycam_project_assignments'), isNull);
  });

  test('damaged project records are skipped without blocking valid projects',
      () async {
    final valid = Project(
      id: 'valid-id',
      name: 'Valid project',
      createdAtMs: 1,
      updatedAtMs: 1,
    );
    SharedPreferences.setMockInitialValues({
      'surveycam_projects': ['damaged json', jsonEncode(valid.toJson())],
    });

    final controller = ProjectController();
    addTearDown(controller.dispose);
    await controller.ready;

    expect(controller.state.isLoading, isFalse);
    expect(
        controller.state.projects.map((project) => project.id), ['valid-id']);
  });

  test('project names are unique and projects can be renamed and deleted',
      () async {
    final controller = ProjectController();
    addTearDown(controller.dispose);
    await controller.ready;

    final project = await controller.createProject('Site A');
    await expectLater(
      controller.createProject(' site a '),
      throwsArgumentError,
    );

    await controller.renameProject(project.id, 'Site B');
    expect(controller.state.activeProject?.name, 'Site B');

    final file = File('C:/captures/site-b.jpg');
    await controller.assignFileToActiveProject(file);
    await controller.deleteProject(project.id);
    expect(controller.state.projects, isEmpty);
    expect(controller.state.activeProjectId, isNull);
    expect(controller.state.assignments, isEmpty);
  });

  test('filtered gallery reacts immediately when active project changes',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('surveycam_project_');
    addTearDown(() => directory.delete(recursive: true));
    final projectFile = File('${directory.path}/SurveyCam_project.jpg');
    final otherFile = File('${directory.path}/SurveyCam_other.jpg');
    await projectFile.writeAsBytes([1]);
    await otherFile.writeAsBytes([2]);

    final repository = SurveyCamGalleryRepository(
      localAlbumDirectory: () async => directory,
      mediaStoreFiles: () async => const [],
      isAndroid: false,
      isIOS: false,
    );
    final container = ProviderContainer(
      overrides: [galleryRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container
        .read(galleryFilesProvider.notifier)
        .ensureLoaded(forceRefresh: true);

    expect(container.read(filteredGalleryFilesProvider), hasLength(2));
    final controller = container.read(projectProvider.notifier);
    await controller.ready;
    await controller.createProject('Reactive project');
    await controller.assignFileToActiveProject(projectFile);

    final filtered = container.read(filteredGalleryFilesProvider);
    expect(filtered, hasLength(1));
    expect(p.normalize(filtered.single.path), p.normalize(projectFile.path));
    await controller.setActiveProject(null);
    expect(container.read(filteredGalleryFilesProvider), hasLength(2));
  });
}
