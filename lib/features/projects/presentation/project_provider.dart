import 'dart:io';

import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';

import '../data/project_storage.dart';
import '../domain/project.dart';

final projectProvider =
    StateNotifierProvider<ProjectController, ProjectState>((ref) {
  return ProjectController();
});

class ProjectState {
  final bool isLoading;
  final List<Project> projects;
  final String? activeProjectId;
  final Map<String, String> assignments;

  const ProjectState({
    this.isLoading = true,
    this.projects = const <Project>[],
    this.activeProjectId,
    this.assignments = const <String, String>{},
  });

  Project? get activeProject {
    final id = activeProjectId;
    if (id == null) return null;
    for (final project in projects) {
      if (project.id == id) return project;
    }
    return null;
  }

  List<File> filterFilesForActiveProject(List<File> files) {
    final projectId = activeProjectId;
    if (projectId == null) return files;

    return files
        .where((file) =>
            assignments[ProjectStorage.assignmentKeyForFile(file)] == projectId)
        .toList(growable: false);
  }

  ProjectState copyWith({
    bool? isLoading,
    List<Project>? projects,
    String? activeProjectId,
    bool clearActiveProject = false,
    Map<String, String>? assignments,
  }) {
    return ProjectState(
      isLoading: isLoading ?? this.isLoading,
      projects: projects ?? this.projects,
      activeProjectId:
          clearActiveProject ? null : (activeProjectId ?? this.activeProjectId),
      assignments: assignments ?? this.assignments,
    );
  }
}

class ProjectController extends StateNotifier<ProjectState> {
  ProjectController() : super(const ProjectState()) {
    _load();
  }

  final _storage = ProjectStorage();
  final _uuid = const Uuid();

  Future<void> _load() async {
    final projects = await _storage.loadProjects();
    final assignments = await _storage.loadAssignments();
    final activeProjectId = await _storage.loadActiveProjectId();
    final activeExists =
        projects.any((project) => project.id == activeProjectId);

    state = ProjectState(
      isLoading: false,
      projects: projects,
      activeProjectId: activeExists ? activeProjectId : null,
      assignments: assignments,
    );
  }

  Future<Project> createProject(String name) async {
    final cleaned = name.trim();
    if (cleaned.isEmpty) {
      throw ArgumentError('Project name cannot be empty');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final project = Project(
      id: _uuid.v4(),
      name: cleaned,
      createdAtMs: now,
      updatedAtMs: now,
    );
    final projects = [project, ...state.projects];
    state = state.copyWith(projects: projects, activeProjectId: project.id);
    await _storage.saveProjects(projects);
    await _storage.saveActiveProjectId(project.id);
    return project;
  }

  Future<void> setActiveProject(String? projectId) async {
    final exists = projectId == null ||
        state.projects.any((project) => project.id == projectId);
    if (!exists) return;

    state = projectId == null
        ? state.copyWith(clearActiveProject: true)
        : state.copyWith(activeProjectId: projectId);
    await _storage.saveActiveProjectId(projectId);
  }

  Future<void> assignFileToActiveProject(File file, {File? replace}) async {
    final projectId = state.activeProjectId;
    await assignFileToProject(file, projectId: projectId, replace: replace);
  }

  Future<void> assignFileToProject(
    File file, {
    required String? projectId,
    File? replace,
  }) async {
    final assignments = Map<String, String>.from(state.assignments);
    if (replace != null) {
      assignments.remove(ProjectStorage.assignmentKeyForFile(replace));
    }
    final key = ProjectStorage.assignmentKeyForFile(file);
    if (projectId == null || projectId.isEmpty) {
      assignments.remove(key);
    } else {
      assignments[key] = projectId;
    }
    state = state.copyWith(assignments: assignments);
    await _storage.assignFilePath(
      filePath: file.path,
      projectId: projectId,
      replacePath: replace?.path,
    );
  }

  List<File> filterFilesForActiveProject(List<File> files) {
    return state.filterFilesForActiveProject(files);
  }
}
