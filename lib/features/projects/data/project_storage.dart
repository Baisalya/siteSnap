import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/project.dart';

class ProjectStorage {
  static const _projectsKey = 'surveycam_projects';
  static const _activeProjectKey = 'surveycam_active_project_id';
  static const _assignmentsKey = 'surveycam_project_assignments';
  static const _assignmentEntryPrefix = 'surveycam_project_assignment_v2:';

  final _ProjectPreferences _prefs = _ProjectPreferences();

  Future<List<Project>> loadProjects() async {
    final raw = await _prefs.getStringList(_projectsKey) ?? const <String>[];
    final projects = <Project>[];
    for (final item in raw) {
      try {
        final project =
            Project.fromJson(jsonDecode(item) as Map<String, dynamic>);
        if (project.id.isNotEmpty && project.name.trim().isNotEmpty) {
          projects.add(project);
        }
      } catch (_) {
        // Ignore one damaged record instead of making every project unusable.
      }
    }
    return projects;
  }

  Future<void> saveProjects(List<Project> projects) async {
    await _prefs.setStringList(
      _projectsKey,
      projects.map((project) => jsonEncode(project.toJson())).toList(),
    );
  }

  Future<String?> loadActiveProjectId() async {
    final value = await _prefs.getString(_activeProjectKey);
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> saveActiveProjectId(String? projectId) async {
    if (projectId == null || projectId.isEmpty) {
      await _prefs.remove(_activeProjectKey);
    } else {
      await _prefs.setString(_activeProjectKey, projectId);
    }
  }

  Future<Map<String, String>> loadAssignments() async {
    await _migrateLegacyAssignments();
    final assignments = <String, String>{};
    final keys = await _prefs.getKeys();
    for (final key
        in keys.where((key) => key.startsWith(_assignmentEntryPrefix))) {
      try {
        final raw = await _prefs.getString(key);
        if (raw == null || raw.isEmpty) continue;
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final path = decoded['path'] as String?;
        final projectId = decoded['projectId'] as String?;
        if (path == null ||
            path.isEmpty ||
            projectId == null ||
            projectId.isEmpty) {
          await _prefs.remove(key);
          continue;
        }
        assignments[path] = projectId;
      } catch (_) {
        await _prefs.remove(key);
      }
    }
    return assignments;
  }

  Future<void> saveAssignments(Map<String, String> assignments) async {
    final keys = await _prefs.getKeys();
    for (final key
        in keys.where((key) => key.startsWith(_assignmentEntryPrefix))) {
      await _prefs.remove(key);
    }
    for (final entry in assignments.entries) {
      await _writeAssignment(entry.key, entry.value);
    }
  }

  Future<void> assignFilePath({
    required String filePath,
    required String? projectId,
    String? replacePath,
  }) async {
    if (replacePath != null && replacePath.isNotEmpty) {
      await _removeAssignment(replacePath);
    }

    final key = _assignmentKey(filePath);
    if (projectId == null || projectId.isEmpty) {
      await _removeAssignment(filePath);
    } else {
      await _writeAssignment(key, projectId);
    }
  }

  Future<void> removeAssignmentsForProject(String projectId) async {
    final assignments = await loadAssignments();
    for (final entry in assignments.entries) {
      if (entry.value == projectId) {
        await _prefs.remove(_entryKey(entry.key));
      }
    }
  }

  Future<void> _migrateLegacyAssignments() async {
    final raw = await _prefs.getString(_assignmentsKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        final projectId = entry.value.toString();
        if (entry.key.isNotEmpty && projectId.isNotEmpty) {
          await _writeAssignment(entry.key, projectId);
        }
      }
    } catch (_) {
      // A damaged legacy blob must not block new per-file assignments.
    } finally {
      await _prefs.remove(_assignmentsKey);
    }
  }

  Future<void> _writeAssignment(String normalizedPath, String projectId) {
    return _prefs.setString(
      _entryKey(normalizedPath),
      jsonEncode({'path': normalizedPath, 'projectId': projectId}),
    );
  }

  Future<void> _removeAssignment(String path) async {
    final normalized = _assignmentKey(path);
    await _prefs.remove(_entryKey(normalized));
    final legacy = _legacyAssignmentKey(path);
    if (legacy != normalized) {
      await _prefs.remove(_entryKey(legacy));
    }
  }

  static String _entryKey(String normalizedPath) {
    final encoded = base64Url.encode(utf8.encode(normalizedPath));
    return '$_assignmentEntryPrefix$encoded';
  }

  static String assignmentKeyForFile(File file) => _assignmentKey(file.path);

  static String legacyAssignmentKeyForFile(File file) =>
      _legacyAssignmentKey(file.path);

  static String _assignmentKey(String path) {
    final normalized = p.normalize(path);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  static String _legacyAssignmentKey(String path) =>
      p.normalize(path).toLowerCase();
}

class _ProjectPreferences {
  _ProjectPreferences() {
    try {
      _async = SharedPreferencesAsync();
    } on StateError {
      // Flutter unit tests use SharedPreferences.setMockInitialValues, which
      // configures the legacy backend but not SharedPreferencesAsyncPlatform.
    }
  }

  SharedPreferencesAsync? _async;

  Future<List<String>?> getStringList(String key) async {
    final async = _async;
    if (async != null) return async.getStringList(key);
    return (await _legacy()).getStringList(key);
  }

  Future<String?> getString(String key) async {
    final async = _async;
    if (async != null) return async.getString(key);
    return (await _legacy()).getString(key);
  }

  Future<Set<String>> getKeys() async {
    final async = _async;
    if (async != null) return async.getKeys();
    return (await _legacy()).getKeys();
  }

  Future<void> setStringList(String key, List<String> value) async {
    final async = _async;
    if (async != null) {
      await async.setStringList(key, value);
      return;
    }
    await (await _legacy()).setStringList(key, value);
  }

  Future<void> setString(String key, String value) async {
    final async = _async;
    if (async != null) {
      await async.setString(key, value);
      return;
    }
    await (await _legacy()).setString(key, value);
  }

  Future<void> remove(String key) async {
    final async = _async;
    if (async != null) {
      await async.remove(key);
      return;
    }
    await (await _legacy()).remove(key);
  }

  Future<SharedPreferences> _legacy() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs;
  }
}
