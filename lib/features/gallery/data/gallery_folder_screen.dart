import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:share_plus/share_plus.dart';
import 'package:surveycam/core/monetization/premium_feature.dart';
import 'package:surveycam/core/monetization/premium_policy.dart';
import 'package:surveycam/core/permissions/permission_service.dart';
import 'package:surveycam/core/services/pdf_proof_report_service.dart';
import 'package:surveycam/core/utils/thumbnail_utils.dart';
import 'package:surveycam/features/gallery/data/sitesnap_gallery_repository.dart';
import 'package:surveycam/features/gallery/presentation/gallery_image_viewer.dart';
import 'package:surveycam/features/gallery/presentation/video_player_screen.dart';
import 'package:surveycam/features/projects/presentation/project_picker_sheet.dart';
import 'package:surveycam/features/projects/presentation/project_provider.dart';

final gallerySelectionProvider = StateProvider<Set<File>>((ref) => {});

class GalleryFolderScreen extends ConsumerStatefulWidget {
  const GalleryFolderScreen({super.key});

  @override
  ConsumerState<GalleryFolderScreen> createState() =>
      _GalleryFolderScreenState();
}

class _GalleryFolderScreenState extends ConsumerState<GalleryFolderScreen>
    with WidgetsBindingObserver {
  bool _isExportingPdf = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() async {
      await PermissionService.requestGalleryAccessIfNeeded();
      if (!mounted) return;
      await ref
          .read(galleryFilesProvider.notifier)
          .ensureLoaded(forceRefresh: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(galleryFilesProvider.notifier).ensureLoaded();
    }
  }

  /// ================= SHARE =================
  void _shareSelected() {
    final selectedImages = ref.read(gallerySelectionProvider);
    if (selectedImages.isEmpty) {
      _showSnack('Select images to share.');
      return;
    }

    SharePlus.instance.share(
      ShareParams(
        files: selectedImages.map((f) => XFile(f.path)).toList(),
        text: "Shared from SurveyCam 📷",
      ),
    );
  }

  /// ================= SELECT =================
  Future<void> _showPdfTemplateSheet() async {
    if (_isExportingPdf) return;

    final selectedImages = ref.read(gallerySelectionProvider);
    if (selectedImages.isEmpty) {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => const _PdfSelectionHelpSheet(),
      );
      return;
    }

    final canUsePdfReports =
        ref.read(premiumPolicyProvider).canUse(PremiumFeature.pdfReports);
    if (!canUsePdfReports) {
      _showSnack('PDF proof reports are a SurveyCam Pro feature.');
      return;
    }

    final selectedFiles = selectedImages.toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final activeProject = ref.read(projectProvider).activeProject;

    final details = await showModalBottomSheet<_PdfReportDetails>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PdfReportDetailsSheet(
        files: selectedFiles,
        initialProjectName: activeProject?.name ?? '',
      ),
    );

    if (details != null && mounted) {
      await _exportSelectedPdf(details);
    }
  }

  Future<void> _exportSelectedPdf(_PdfReportDetails details) async {
    if (details.files.isEmpty) return;

    setState(() => _isExportingPdf = true);
    try {
      final report = await const PdfProofReportService().createReport(
        files: details.files,
        reportTitle: details.reportTitle,
        projectName: details.projectName,
        photoDescriptions: details.photoDescriptions,
        template: details.template,
      );

      if (!mounted) return;
      setState(() => _isExportingPdf = false);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(report.path)],
          text: 'SurveyCam PDF proof report',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showSnack('Could not create PDF report: $error');
    } finally {
      if (mounted) {
        setState(() => _isExportingPdf = false);
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _selectAll(List<File> images) {
    ref.read(gallerySelectionProvider.notifier).state = images.toSet();
  }

  void _clearSelection() {
    ref.read(gallerySelectionProvider.notifier).state = {};
  }

  /// ================= BUILD =================
  @override
  Widget build(BuildContext context) {
    final galleryAsync = ref.watch(galleryFilesProvider);
    final projectState = ref.watch(projectProvider);
    final activeProject = projectState.activeProject;
    final selectedImages = ref.watch(gallerySelectionProvider);
    final selectionMode = selectedImages.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,

      /// ================= APPBAR =================
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.black,
        leading: selectionMode
            ? IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: _clearSelection,
              )
            : null,
        title: selectionMode
            ? Text(
                "${selectedImages.length} selected",
                style: const TextStyle(color: Colors.white),
              )
            : Text(
                activeProject?.name ?? "SurveyCam Gallery",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
        actions: [
          if (selectionMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all, color: Colors.white),
              onPressed: () {
                galleryAsync.whenData(
                  (images) => _selectAll(
                    projectState.filterFilesForActiveProject(images),
                  ),
                );
              },
            ),
            if (_isExportingPdf)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.amberAccent,
                  ),
                ),
              )
            else
              _PdfActionButton(
                onPressed: _showPdfTemplateSheet,
              ),
            IconButton(
              icon: const Icon(Icons.share, color: Colors.white),
              onPressed: _shareSelected,
            ),
          ] else ...[
            _PdfActionButton(
              onPressed: _showPdfTemplateSheet,
            ),
            IconButton(
              tooltip: 'Project folders',
              icon: const Icon(
                Icons.folder_special_rounded,
                color: Colors.amberAccent,
              ),
              onPressed: () => showProjectPickerSheet(context),
            ),
          ],
        ],
      ),

      /// ================= BODY =================
      body: galleryAsync.when(
        data: (images) {
          final filteredImages =
              projectState.filterFilesForActiveProject(images);
          if (filteredImages.isEmpty) return _emptyView(activeProject?.name);

          return _galleryGridWithHint(
            images: filteredImages,
            showHint: !selectionMode,
          );
        },
        loading: () {
          final cachedImages =
              ref.read(galleryRepositoryProvider).cachedFiles ?? const <File>[];
          final filteredImages =
              projectState.filterFilesForActiveProject(cachedImages);
          return filteredImages.isEmpty
              ? _loadingView()
              : _galleryGridWithHint(
                  images: filteredImages,
                  showHint: !selectionMode,
                );
        },
        error: (err, stack) => Center(
          child: Text("Error: $err", style: const TextStyle(color: Colors.red)),
        ),
      ),
    );
  }

  Widget _galleryGridWithHint({
    required List<File> images,
    required bool showHint,
  }) {
    return Stack(
      children: [
        _galleryGrid(images),
        if (showHint) const _PdfExportHint(),
      ],
    );
  }

  Widget _galleryGrid(List<File> images) {
    return RefreshIndicator(
      onRefresh: () => ref.read(galleryFilesProvider.notifier).refresh(),
      color: Colors.amberAccent,
      backgroundColor: Colors.grey[900],
      child: GridView.builder(
        padding: const EdgeInsets.all(6),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
        ),
        itemCount: images.length,
        itemBuilder: (context, i) {
          final file = images[i];
          return GalleryItem(
            key: ValueKey(file.path),
            file: file,
            index: i,
            allImages: images,
          );
        },
      ),
    );
  }

  /// ================= LOADING =================
  Widget _loadingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 12),
          Text(
            "Loading photos...",
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }

  /// ================= EMPTY =================
  Widget _emptyView(String? projectName) {
    final title = projectName == null ? "No photos yet" : "No project photos";
    final subtitle = projectName == null
        ? "Capture photos to see them here"
        : "New captures will be saved in $projectName";

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.photo_library_outlined,
            size: 64,
            color: Colors.white38,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38),
          ),
        ],
      ),
    );
  }
}

class _PdfExportHint extends StatelessWidget {
  const _PdfExportHint();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 14,
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: Colors.amberAccent.withValues(alpha: 0.42),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.picture_as_pdf_rounded,
                    color: Colors.amberAccent,
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Long press photos to make a PDF proof report',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PdfActionButton extends StatelessWidget {
  const _PdfActionButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            tooltip: 'PDF proof report',
            icon: const Icon(
              Icons.picture_as_pdf_rounded,
              color: Colors.amberAccent,
            ),
            onPressed: onPressed,
          ),
          Positioned(
            top: 4,
            right: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.black, width: 1.2),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                child: Text(
                  'NEW',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 7,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PdfSelectionHelpSheet extends StatelessWidget {
  const _PdfSelectionHelpSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                const Icon(
                  Icons.photo_library_rounded,
                  color: Colors.amberAccent,
                  size: 38,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Select pictures to create PDF',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Long press a photo, select one or more pictures, then tap the PDF button again to add title, project name, and photo descriptions.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Got it'),
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
}

class _PdfReportDetails {
  const _PdfReportDetails({
    required this.files,
    required this.reportTitle,
    required this.projectName,
    required this.template,
    required this.photoDescriptions,
  });

  final List<File> files;
  final String reportTitle;
  final String projectName;
  final ProofReportTemplate template;
  final Map<String, String> photoDescriptions;
}

class _PdfReportDetailsSheet extends StatefulWidget {
  const _PdfReportDetailsSheet({
    required this.files,
    required this.initialProjectName,
  });

  final List<File> files;
  final String initialProjectName;

  @override
  State<_PdfReportDetailsSheet> createState() => _PdfReportDetailsSheetState();
}

class _PdfReportDetailsSheetState extends State<_PdfReportDetailsSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _projectController;
  late final Map<String, TextEditingController> _descriptionControllers;
  ProofReportTemplate _template = ProofReportTemplate.standard;

  @override
  void initState() {
    super.initState();
    final project = widget.initialProjectName.trim();
    _titleController = TextEditingController(
      text:
          project.isEmpty ? 'SurveyCam Proof Report' : '$project Proof Report',
    );
    _projectController = TextEditingController(text: project);
    _descriptionControllers = {
      for (final file in widget.files) file.path: TextEditingController(),
    };
  }

  @override
  void dispose() {
    _titleController.dispose();
    _projectController.dispose();
    for (final controller in _descriptionControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 14,
          right: 14,
          top: 14,
          bottom: MediaQuery.of(context).viewInsets.bottom + 14,
        ),
        child: Material(
          color: const Color(0xFF171717),
          borderRadius: BorderRadius.circular(22),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.88,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                  child: Column(
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
                          const Icon(
                            Icons.picture_as_pdf_rounded,
                            color: Colors.amberAccent,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'PDF Proof Report',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                    children: [
                      _ReportTextField(
                        controller: _titleController,
                        label: 'Report title',
                        icon: Icons.title_rounded,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 10),
                      _ReportTextField(
                        controller: _projectController,
                        label: 'Project name',
                        icon: Icons.business_center_rounded,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Template',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _PdfTemplateChoice(
                        icon: Icons.article_rounded,
                        title: 'Standard report',
                        subtitle: 'Large photo proof with full file details',
                        selected: _template == ProofReportTemplate.standard,
                        onTap: () => setState(
                          () => _template = ProofReportTemplate.standard,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _PdfTemplateChoice(
                        icon: Icons.grid_view_rounded,
                        title: 'Compact report',
                        subtitle: 'Two-column summary for more photos per page',
                        selected: _template == ProofReportTemplate.compact,
                        onTap: () => setState(
                          () => _template = ProofReportTemplate.compact,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Photo descriptions',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final file in widget.files) ...[
                        _PhotoDescriptionField(
                          file: file,
                          controller: _descriptionControllers[file.path]!,
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.picture_as_pdf_rounded),
                      label: const Text('Generate PDF'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amberAccent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
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

  void _submit() {
    final descriptions = <String, String>{};
    for (final entry in _descriptionControllers.entries) {
      final text = entry.value.text.trim();
      if (text.isNotEmpty) {
        descriptions[entry.key] = text;
      }
    }

    Navigator.pop(
      context,
      _PdfReportDetails(
        files: widget.files,
        reportTitle: _titleController.text.trim(),
        projectName: _projectController.text.trim(),
        template: _template,
        photoDescriptions: descriptions,
      ),
    );
  }
}

class _PdfTemplateChoice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _PdfTemplateChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      tileColor: selected
          ? Colors.amberAccent.withValues(alpha: 0.16)
          : Colors.white.withValues(alpha: 0.05),
      leading: Icon(icon, color: Colors.amberAccent),
      title: Text(
        title,
        style:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
      trailing: selected
          ? const Icon(Icons.check_circle_rounded, color: Colors.amberAccent)
          : const Icon(Icons.circle_outlined, color: Colors.white24),
    );
  }
}

class _ReportTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputAction textInputAction;

  const _ReportTextField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: textInputAction,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Icon(icon, color: Colors.white54),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _PhotoDescriptionField extends StatelessWidget {
  final File file;
  final TextEditingController controller;

  const _PhotoDescriptionField({
    required this.file,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final fileName =
        file.uri.pathSegments.isEmpty ? file.path : file.uri.pathSegments.last;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.photo_library_rounded,
                  color: Colors.amberAccent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              minLines: 2,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Write photo description or site observation',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.22),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GalleryItem extends ConsumerWidget {
  final File file;
  final int index;
  final List<File> allImages;

  const GalleryItem({
    super.key,
    required this.file,
    required this.index,
    required this.allImages,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedImages = ref.watch(gallerySelectionProvider);
    final isSelected = selectedImages.contains(file);
    final selectionMode = selectedImages.isNotEmpty;

    final isVideo = file.path.toLowerCase().endsWith('.mp4') ||
        file.path.toLowerCase().endsWith('.mov');
    final processingItem = ref.watch(
      galleryProcessingProvider.select((items) => items[file.path]),
    );
    final isProcessing = processingItem?.isProcessing ?? false;
    final processingFailed = processingItem?.failed ?? false;

    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onLongPress: () {
            ref
                .read(gallerySelectionProvider.notifier)
                .update((state) => <File>{...state, file});
          },
          onTap: () {
            if (selectionMode) {
              ref.read(gallerySelectionProvider.notifier).update((state) {
                final newState = {...state};
                if (newState.contains(file)) {
                  newState.remove(file);
                } else {
                  newState.add(file);
                }
                return newState;
              });
            } else {
              if (isVideo) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VideoPlayerScreen(file: file),
                  ),
                );
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GalleryImageViewer(
                      images: allImages,
                      initialIndex: index,
                    ),
                  ),
                );
              }
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border:
                  isSelected ? Border.all(color: Colors.blue, width: 2) : null,
            ),
            child: Stack(
              children: [
                /// 🔥 HERO IMAGE / THUMBNAIL
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Hero(
                    tag: file.path,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 450),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: isVideo
                          ? VideoThumbnailWidget(
                              key: ValueKey(file.path),
                              videoPath: file.path,
                            )
                          : Image.file(
                              file,
                              key: ValueKey(file.path),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              cacheWidth: 300,
                            ),
                    ),
                  ),
                ),

                /// Play icon for videos
                if (isVideo)
                  const Center(
                    child: Icon(
                      Icons.play_circle_outline,
                      color: Colors.white70,
                      size: 32,
                    ),
                  ),

                /// overlay
                if (isSelected)
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.black.withValues(alpha: 0.4),
                    ),
                  ),

                /// check icon
                if (isSelected)
                  const Positioned(
                    top: 6,
                    right: 6,
                    child: CircleAvatar(
                      radius: 10,
                      backgroundColor: Colors.blue,
                      child: Icon(
                        Icons.check,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),

                if (isProcessing || processingFailed)
                  Positioned.fill(
                    child: _ProcessingOverlay(failed: processingFailed),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProcessingOverlay extends StatelessWidget {
  final bool failed;

  const _ProcessingOverlay({required this.failed});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.12),
              Colors.black.withValues(alpha: 0.64),
            ],
          ),
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.14),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (failed)
                      const Icon(
                        Icons.error_outline,
                        color: Colors.orangeAccent,
                        size: 14,
                      )
                    else
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        failed ? 'Raw saved' : 'Adding overlay',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class VideoThumbnailWidget extends StatefulWidget {
  final String videoPath;
  const VideoThumbnailWidget({super.key, required this.videoPath});

  @override
  State<VideoThumbnailWidget> createState() => _VideoThumbnailWidgetState();
}

class _VideoThumbnailWidgetState extends State<VideoThumbnailWidget> {
  late Future<String?> _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = ThumbnailUtils.generateVideoThumbnail(widget.videoPath);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _thumbnailFuture,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.file(
            File(snapshot.data!),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            cacheWidth: 300,
          );
        }
        return Container(
          color: Colors.grey[900],
          child: const Icon(Icons.video_library, color: Colors.white24),
        );
      },
    );
  }
}
