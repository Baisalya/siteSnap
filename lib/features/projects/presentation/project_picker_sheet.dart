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

class ProjectPickerSheet extends ConsumerStatefulWidget {
  const ProjectPickerSheet({super.key});

  @override
  ConsumerState<ProjectPickerSheet> createState() => _ProjectPickerSheetState();
}

class _ProjectPickerSheetState extends ConsumerState<ProjectPickerSheet> {
  final _controller = TextEditingController();

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
                  onTap: canUseProjects
                      ? () async {
                          await ref
                              .read(projectProvider.notifier)
                              .setActiveProject(null);
                          if (context.mounted) Navigator.pop(context);
                        }
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
                          onTap: canUseProjects
                              ? () async {
                                  await ref
                                      .read(projectProvider.notifier)
                                      .setActiveProject(project.id);
                                  if (context.mounted) Navigator.pop(context);
                                }
                              : null,
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _controller,
                  enabled: canUseProjects,
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
                    onPressed:
                        canUseProjects ? () => _createProject(context) : null,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Create Project'),
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
    if (name.isEmpty) return;
    await ref.read(projectProvider.notifier).createProject(name);
    _controller.clear();
    if (context.mounted) Navigator.pop(context);
  }
}

class _ProjectTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  const _ProjectTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
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
      trailing: selected
          ? const Icon(Icons.check_circle_rounded, color: Colors.amberAccent)
          : null,
    );
  }
}
