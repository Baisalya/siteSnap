import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/project.dart';

class ProjectStorage {
  static const _projectsKey = 'surveycam_projects';
  static const _activeProjectKey = 'surveycam_active_project_id';
  static const _assignmentsKey = 'surveycam_project_assignments';

  Future<List<Project>> loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_projectsKey) ?? const <String>[];
    return raw
        .map((item) =>
            Project.fromJson(jsonDecode(item) as Map<String, dynamic>))
        .where((project) => project.id.isNotEmpty && project.name.isNotEmpty)
        .toList();
  }

  Future<void> saveProjects(List<Project> projects) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _projectsKey,
      projects.map((project) => jsonEncode(project.toJson())).toList(),
    );
  }

  Future<String?> loadActiveProjectId() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_activeProjectKey);
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> saveActiveProjectId(String? projectId) async {
    final prefs = await SharedPreferences.getInstance();
    if (projectId == null || projectId.isEmpty) {
      await prefs.remove(_activeProjectKey);
    } else {
      await prefs.setString(_activeProjectKey, projectId);
    }
  }

  Future<Map<String, String>> loadAssignments() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_assignmentsKey);
    if (raw == null || raw.isEmpty) return <String, String>{};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((key, value) => MapEntry(key, value.toString()));
  }

  Future<void> saveAssignments(Map<String, String> assignments) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_assignmentsKey, jsonEncode(assignments));
  }

  Future<void> assignFilePath({
    required String filePath,
    required String? projectId,
    String? replacePath,
  }) async {
    final assignments = await loadAssignments();
    if (replacePath != null && replacePath.isNotEmpty) {
      assignments.remove(_assignmentKey(replacePath));
    }

    final key = _assignmentKey(filePath);
    if (projectId == null || projectId.isEmpty) {
      assignments.remove(key);
    } else {
      assignments[key] = projectId;
    }
    await saveAssignments(assignments);
  }

  static String assignmentKeyForFile(File file) => _assignmentKey(file.path);

  static String _assignmentKey(String path) {
    return p.normalize(path).toLowerCase();
  }
}
