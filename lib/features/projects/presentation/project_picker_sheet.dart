import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:surveycam/core/monetization/premium_feature.dart';
import 'package:surveycam/core/monetization/premium_policy.dart';
import 'project_provider.dart';

Future<void> showProjectPickerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const ProjectPickerSheet(),
  );
}

Future<bool> showProjectAssignmentSheet(
  BuildContext context, {
  required List<File> files,
}) async {
  return await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => _ProjectAssignmentSheet(files: files),
      ) ??
      false;
}

class ProjectPickerSheet extends ConsumerStatefulWidget {
  const ProjectPickerSheet({super.key});

  @override
  ConsumerState<ProjectPickerSheet> createState() => _ProjectPickerSheetState();
}

class _ProjectPickerSheetState extends ConsumerState<ProjectPickerSheet> {
  final _controller = TextEditingController();
  bool _isCreating = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projectState = ref.watch(projectProvider);
    final canUseProjects =
        ref.watch(premiumPolicyProvider).canUse(PremiumFeature.projectFolders);
    final projectsEnabled = canUseProjects && !projectState.isLoading;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 14,
          right: 14,
          bottom: MediaQuery.of(context).viewInsets.bottom + 14,
        ),
        child: Material(
          color: const Color(0xFF171717),
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.folder_special_rounded,
                        color: Colors.amberAccent),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Project Folder',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white54),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _ProjectTile(
                  icon: Icons.all_inbox_rounded,
                  title: 'All captures',
                  subtitle: 'No project filter',
                  selected: projectState.activeProjectId == null,
                  onTap: !projectState.isLoading
                      ? () => _selectProject(context, null)
                      : null,
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: projectState.projects.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final project = projectState.projects[index];
                        return _ProjectTile(
                          icon: Icons.folder_rounded,
                          title: project.name,
                          subtitle: 'Use for new captures',
                          selected: project.id == projectState.activeProjectId,
                          action: projectsEnabled
                              ? PopupMenuButton<_ProjectAction>(
                                  tooltip: 'Project options',
                                  color: const Color(0xFF2A2A2A),
                                  icon: const Icon(
                                    Icons.more_vert_rounded,
                                    color: Colors.white54,
                                  ),
                                  onSelected: (action) {
                                    if (action == _ProjectAction.rename) {
                                      _renameProject(
                                          context, project.id, project.name);
                                    } else {
                                      _deleteProject(
                                          context, project.id, project.name);
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: _ProjectAction.rename,
                                      child: Text('Rename',
                                          style:
                                              TextStyle(color: Colors.white)),
                                    ),
                                    PopupMenuItem(
                                      value: _ProjectAction.delete,
                                      child: Text('Delete',
                                          style: TextStyle(
                                              color: Colors.redAccent)),
                                    ),
                                  ],
                                )
                              : null,
                          onTap: projectsEnabled
                              ? () => _selectProject(context, project.id)
                              : null,
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _controller,
                  enabled: projectsEnabled && !_isCreating,
                  maxLength: 80,
                  textInputAction: TextInputAction.done,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'New project name',
                    hintStyle: const TextStyle(color: Colors.white30),
                    prefixIcon: const Icon(Icons.create_new_folder,
                        color: Colors.white54),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _createProject(context),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: projectsEnabled && !_isCreating
                        ? () => _createProject(context)
                        : null,
                    icon: _isCreating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_rounded),
                    label: Text(_isCreating ? 'Creating…' : 'Create Project'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amberAccent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createProject(BuildContext context) async {
    final name = _controller.text.trim();
    if (name.isEmpty || _isCreating) return;
    setState(() => _isCreating = true);
    try {
      await ref.read(projectProvider.notifier).createProject(name);
      _controller.clear();
      if (context.mounted) Navigator.pop(context);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _selectProject(BuildContext context, String? projectId) async {
    try {
      await ref.read(projectProvider.notifier).setActiveProject(projectId);
      if (context.mounted) Navigator.pop(context);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _renameProject(
    BuildContext context,
    String projectId,
    String currentName,
  ) async {
    final controller = TextEditingController(text: currentName);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF242424),
        title:
            const Text('Rename project', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(labelText: 'Project name'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim() == currentName) return;
    try {
      await ref.read(projectProvider.notifier).renameProject(projectId, name);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _deleteProject(
    BuildContext context,
    String projectId,
    String projectName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF242424),
        title: const Text('Delete project?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Captures will remain in the gallery, but “$projectName” and its assignments will be removed.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(projectProvider.notifier).deleteProject(projectId);
      } catch (error) {
        if (context.mounted) _showError(context, error);
      }
    }
  }

  void _showError(BuildContext context, Object error) {
    final message = error is ArgumentError
        ? error.message?.toString() ?? 'Invalid project name.'
        : 'Could not update project. Please try again.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

enum _ProjectAction { rename, delete }

class _ProjectAssignmentSheet extends ConsumerStatefulWidget {
  const _ProjectAssignmentSheet({required this.files});

  final List<File> files;

  @override
  ConsumerState<_ProjectAssignmentSheet> createState() =>
      _ProjectAssignmentSheetState();
}

class _ProjectAssignmentSheetState
    extends ConsumerState<_ProjectAssignmentSheet> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(projectProvider);
    final canUseProjects =
        ref.watch(premiumPolicyProvider).canUse(PremiumFeature.projectFolders);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Material(
          color: const Color(0xFF171717),
          borderRadius: BorderRadius.circular(22),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 10, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.drive_file_move_rounded,
                          color: Colors.amberAccent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Assign ${widget.files.length} capture${widget.files.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (_saving)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else
                        IconButton(
                          onPressed: () => Navigator.pop(context, false),
                          icon: const Icon(Icons.close, color: Colors.white54),
                        ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    children: [
                      _assignmentTile(
                        icon: Icons.folder_off_rounded,
                        title: 'No project',
                        enabled: !state.isLoading && !_saving,
                        onTap: () => _assign(null),
                      ),
                      for (final project in state.projects)
                        _assignmentTile(
                          icon: Icons.folder_rounded,
                          title: project.name,
                          enabled:
                              canUseProjects && !state.isLoading && !_saving,
                          onTap: () => _assign(project.id),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _assignmentTile({
    required IconData icon,
    required String title,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return ListTile(
      enabled: enabled,
      onTap: enabled ? onTap : null,
      leading: Icon(icon, color: Colors.amberAccent),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white),
      ),
    );
  }

  Future<void> _assign(String? projectId) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final controller = ref.read(projectProvider.notifier);
      for (final file in widget.files) {
        await controller.assignFileToProject(file, projectId: projectId);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update project assignments.')),
      );
    }
  }
}

class _ProjectTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? action;

  const _ProjectTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: onTap != null,
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      tileColor: selected
          ? Colors.amberAccent.withValues(alpha: 0.16)
          : Colors.white.withValues(alpha: 0.05),
      leading:
          Icon(icon, color: selected ? Colors.amberAccent : Colors.white54),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
      trailing: action == null
          ? (selected
              ? const Icon(Icons.check_circle_rounded,
                  color: Colors.amberAccent)
              : null)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected)
                  const Icon(Icons.check_circle_rounded,
                      color: Colors.amberAccent),
                action!,
              ],
            ),
    );
  }
}
