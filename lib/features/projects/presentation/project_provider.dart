import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import 'package:surveycam/core/monetization/premium_feature.dart';
import 'package:surveycam/core/monetization/premium_policy.dart';
import 'package:uuid/uuid.dart';

import '../data/project_storage.dart';
import '../domain/project.dart';

final projectProvider =
    StateNotifierProvider<ProjectController, ProjectState>((ref) {
  return ProjectController();
});

final effectiveActiveProjectProvider = Provider<Project?>((ref) {
  final canUseProjects =
      ref.watch(premiumPolicyProvider).canUse(PremiumFeature.projectFolders);
  return canUseProjects ? ref.watch(projectProvider).activeProject : null;
});

final effectiveActiveProjectIdProvider = Provider<String?>((ref) {
  return ref.watch(effectiveActiveProjectProvider)?.id;
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

    return files.where((file) {
      final key = ProjectStorage.assignmentKeyForFile(file);
      final legacyKey = ProjectStorage.legacyAssignmentKeyForFile(file);
      return (assignments[key] ?? assignments[legacyKey]) == projectId;
    }).toList(growable: false);
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
    _ready = _load();
  }

  final _storage = ProjectStorage();
  final _uuid = const Uuid();
  late final Future<void> _ready;
  Future<void> _mutationQueue = Future<void>.value();

  Future<void> get ready => _ready;

  Future<void> _load() async {
    try {
      final projects = await _storage.loadProjects();
      final assignments = await _storage.loadAssignments();
      final activeProjectId = await _storage.loadActiveProjectId();
      final activeExists =
          projects.any((project) => project.id == activeProjectId);

      if (!mounted) return;
      state = ProjectState(
        isLoading: false,
        projects: projects,
        activeProjectId: activeExists ? activeProjectId : null,
        assignments: assignments,
      );
    } catch (error, stackTrace) {
      debugPrint('Project storage load failed: $error\n$stackTrace');
      if (mounted) {
        state = const ProjectState(isLoading: false);
      }
    }
  }

  Future<Project> createProject(String name) async {
    return _serialize(() async {
      await _ready;
      final cleaned = _validateProjectName(name);
      _ensureUniqueProjectName(cleaned);

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
    });
  }

  Future<void> setActiveProject(String? projectId) async {
    await _serialize(() async {
      await _ready;
      final exists = projectId == null ||
          state.projects.any((project) => project.id == projectId);
      if (!exists) return;

      state = projectId == null
          ? state.copyWith(clearActiveProject: true)
          : state.copyWith(activeProjectId: projectId);
      await _storage.saveActiveProjectId(projectId);
    });
  }

  Future<void> renameProject(String projectId, String name) async {
    await _serialize(() async {
      await _ready;
      final cleaned = _validateProjectName(name);
      _ensureUniqueProjectName(cleaned, exceptProjectId: projectId);
      final index =
          state.projects.indexWhere((project) => project.id == projectId);
      if (index < 0) return;

      final projects = [...state.projects];
      projects[index] = projects[index].copyWith(
        name: cleaned,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      state = state.copyWith(projects: projects);
      await _storage.saveProjects(projects);
    });
  }

  Future<void> deleteProject(String projectId) async {
    await _serialize(() async {
      await _ready;
      if (!state.projects.any((project) => project.id == projectId)) return;

      final projects =
          state.projects.where((project) => project.id != projectId).toList();
      final assignments = Map<String, String>.from(state.assignments)
        ..removeWhere((_, assignedProjectId) => assignedProjectId == projectId);
      final wasActive = state.activeProjectId == projectId;
      state = state.copyWith(
        projects: projects,
        assignments: assignments,
        clearActiveProject: wasActive,
      );
      await _storage.saveProjects(projects);
      await _storage.removeAssignmentsForProject(projectId);
      if (wasActive) {
        await _storage.saveActiveProjectId(null);
      }
    });
  }

  Future<void> assignFileToActiveProject(File file, {File? replace}) async {
    await _ready;
    final projectId = state.activeProjectId;
    await assignFileToProject(file, projectId: projectId, replace: replace);
  }

  Future<void> assignFileToProject(
    File file, {
    required String? projectId,
    File? replace,
  }) async {
    await _serialize(() async {
      await _ready;
      if (projectId != null &&
          !state.projects.any((project) => project.id == projectId)) {
        await _storage.assignFilePath(
          filePath: file.path,
          projectId: null,
          replacePath: replace?.path,
        );
        return;
      }

      final assignments = Map<String, String>.from(state.assignments);
      if (replace != null) {
        assignments.remove(ProjectStorage.assignmentKeyForFile(replace));
        assignments.remove(ProjectStorage.legacyAssignmentKeyForFile(replace));
      }
      final key = ProjectStorage.assignmentKeyForFile(file);
      assignments.remove(ProjectStorage.legacyAssignmentKeyForFile(file));
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
    });
  }

  Future<void> refreshAssignments() async {
    await _serialize(() async {
      await _ready;
      final stored = await _storage.loadAssignments();
      final validProjectIds =
          state.projects.map((project) => project.id).toSet();
      final assignments = <String, String>{};
      for (final entry in stored.entries) {
        if (validProjectIds.contains(entry.value)) {
          assignments[entry.key] = entry.value;
        } else {
          await _storage.assignFilePath(filePath: entry.key, projectId: null);
        }
      }
      if (mounted) {
        state = state.copyWith(assignments: assignments);
      }
    });
  }

  Future<void> reconcileAssignmentsWithFiles(List<File> files) async {
    await _serialize(() async {
      await _ready;
      final stored = await _storage.loadAssignments();
      final validProjectIds =
          state.projects.map((project) => project.id).toSet();
      final canonicalByLegacy = <String, String>{
        for (final file in files)
          ProjectStorage.legacyAssignmentKeyForFile(file):
              ProjectStorage.assignmentKeyForFile(file),
      };
      final canonicalByName = <String, String>{
        for (final file in files)
          p.basename(file.path).toLowerCase():
              ProjectStorage.assignmentKeyForFile(file),
      };
      final reconciled = <String, String>{};

      for (final entry in stored.entries) {
        if (!validProjectIds.contains(entry.value)) {
          await _storage.assignFilePath(filePath: entry.key, projectId: null);
          continue;
        }
        final canonical = canonicalByLegacy[entry.key] ??
            canonicalByName[p.basename(entry.key).toLowerCase()] ??
            entry.key;
        if (canonicalByLegacy.containsValue(canonical) ||
            await File(canonical).exists()) {
          reconciled[canonical] = entry.value;
          if (canonical != entry.key) {
            await _storage.assignFilePath(
              filePath: canonical,
              projectId: entry.value,
              replacePath: entry.key,
            );
          }
        } else {
          await _storage.assignFilePath(filePath: entry.key, projectId: null);
        }
      }

      if (mounted) {
        state = state.copyWith(assignments: reconciled);
      }
    });
  }

  List<File> filterFilesForActiveProject(List<File> files) {
    return state.filterFilesForActiveProject(files);
  }

  String _validateProjectName(String name) {
    final cleaned = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) {
      throw ArgumentError('Project name cannot be empty.');
    }
    if (cleaned.runes.length > 80) {
      throw ArgumentError('Project name must be 80 characters or fewer.');
    }
    return cleaned;
  }

  void _ensureUniqueProjectName(String name, {String? exceptProjectId}) {
    final duplicate = state.projects.any((project) =>
        project.id != exceptProjectId &&
        project.name.trim().toLowerCase() == name.toLowerCase());
    if (duplicate) {
      throw ArgumentError('A project with this name already exists.');
    }
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _mutationQueue = _mutationQueue.catchError((_) {}).then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}
