import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:surveycam/core/services/location_service.dart';
import 'package:surveycam/features/overlay/domain/WatermarkPosition.dart';
import 'package:surveycam/features/overlay/presentation/overlay_preview_state.dart';
import 'package:surveycam/features/overlay/presentation/overlay_settings_provider.dart';
import 'package:surveycam/features/overlay/presentation/saved_notes_provider.dart';

import 'overlay_configuration_screen.dart';

class NoteInputSheet extends ConsumerStatefulWidget {
  const NoteInputSheet({super.key});

  @override
  ConsumerState<NoteInputSheet> createState() => _NoteInputSheetState();
}

class _NoteInputSheetState extends ConsumerState<NoteInputSheet> {
  late TextEditingController locationController;
  late TextEditingController extraNoteController;

  @override
  void initState() {
    super.initState();
    // Initialize with current note if exists
    final currentNote = ref.read(overlayPreviewProvider).note;
    locationController = TextEditingController(
      text: _locationLineFromWatermark(currentNote),
    );
    extraNoteController = TextEditingController(
      text: _extraNoteFromWatermark(currentNote),
    );
  }

  @override
  void dispose() {
    locationController.dispose();
    extraNoteController.dispose();
    super.dispose();
  }

  String _locationLineFromWatermark(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return '';
    return normalized.split(RegExp(r'\r?\n')).first.trim();
  }

  String _extraNoteFromWatermark(String value) {
    final lines = value.trim().split(RegExp(r'\r?\n'));
    if (lines.length <= 1) return '';
    return lines.skip(1).join('\n').trim();
  }

  String _composeWatermarkText() {
    final location = locationController.text.trim();
    final extraNote = extraNoteController.text.trim();

    if (location.isEmpty) return extraNote;
    if (extraNote.isEmpty) return location;
    return "$location\n$extraNote";
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(savedNotesProvider);
    final overlayPreview = ref.watch(overlayPreviewProvider);

    final recent = notes.take(3).toList();
    final allNotes = notes;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.6),
            blurRadius: 20,
            offset: const Offset(0, -5),
          )
        ],
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ───── STICKY HEADER ─────
          _buildHeader(context),

          Flexible(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ───── SEARCH / INPUT SECTION ─────
                  _buildSectionLabel("WATERMARK TEXT"),
                  const SizedBox(height: 12),
                  _buildSearchInput(context),

                  const SizedBox(height: 24),

                  // ───── POSITION SELECTOR ─────
                  _buildSectionLabel("POSITION ON IMAGE"),
                  const SizedBox(height: 12),
                  _buildPositionSelector(overlayPreview.position),

                  const SizedBox(height: 24),

                  _buildSettingsShortcut(context),

                  const SizedBox(height: 24),

                  // ───── RECENT / SAVED NOTES ─────
                  if (recent.isNotEmpty) ...[
                    _buildSectionLabel("RECENTLY USED"),
                    const SizedBox(height: 12),
                    _buildRecentNotes(recent),
                    const SizedBox(height: 24),
                  ],

                  if (allNotes.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSectionLabel("SAVED NOTES"),
                        Text("${allNotes.length} total",
                            style: const TextStyle(
                                color: Colors.white24, fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildSavedNotesList(allNotes),
                  ],

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),

          // ───── FIXED BOTTOM ACTION ─────
          _buildBottomAction(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
            child: Row(
              children: [
                const Icon(Icons.layers_outlined,
                    color: Colors.blueAccent, size: 22),
                const SizedBox(width: 12),
                const Text(
                  "Watermark",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => _openOverlaySettings(context),
                  icon: const Icon(Icons.settings_rounded,
                      color: Colors.blueAccent),
                  tooltip: "Overlay settings",
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.blueAccent.withOpacity(0.1),
                    padding: const EdgeInsets.all(8),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white38),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.05),
                    padding: const EdgeInsets.all(8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withOpacity(0.4),
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.5,
      ),
    );
  }

  Future<void> _openOverlaySettings(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const OverlayConfigurationScreen(),
      ),
    );
  }

  Widget _buildSettingsShortcut(BuildContext context) {
    return InkWell(
      onTap: () => _openOverlaySettings(context),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.blueAccent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.16)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.blueAccent.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.settings_rounded,
                color: Colors.blueAccent,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Overlay Settings",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    "Localization, units, appearance, and visible data",
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchInput(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInputCaption("LINE 1 - AUTOMATIC LOCATION"),
          const SizedBox(height: 8),
          TextField(
            controller: locationController,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Edit location text or tap button to auto-fill',
              hintStyle: const TextStyle(color: Colors.white24),
              prefixIcon: const Icon(
                Icons.place_outlined,
                color: Colors.blueAccent,
                size: 22,
              ),
              suffixIcon: IconButton(
                icon: const Icon(
                  Icons.my_location_rounded,
                  color: Colors.blueAccent,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.blueAccent.withOpacity(0.1),
                ),
                onPressed: () => _fetchLocation(context),
              ),
              filled: true,
              fillColor: Colors.black.withOpacity(0.18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          _buildInputCaption("LINE 2 - EXTRA NOTE"),
          const SizedBox(height: 8),
          TextField(
            controller: extraNoteController,
            minLines: 2,
            maxLines: 4,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Write additional note here...',
              hintStyle: const TextStyle(color: Colors.white24),
              prefixIcon: const Padding(
                padding: EdgeInsets.only(bottom: 42),
                child: Icon(
                  Icons.edit_note_rounded,
                  color: Colors.blueAccent,
                  size: 24,
                ),
              ),
              suffixIcon: extraNoteController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(
                        Icons.clear,
                        color: Colors.white24,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => extraNoteController.clear()),
                    ),
              filled: true,
              fillColor: Colors.black.withOpacity(0.18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Text(
            "Overlay preview: automatic location first, extra note starts on the next line.",
            style: TextStyle(
              color: Colors.white.withOpacity(0.38),
              fontSize: 11,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputCaption(String text) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.blueAccent.withOpacity(0.9),
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildPositionSelector(WatermarkPosition current) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          _positionOption(WatermarkPosition.bottomLeft, "Bottom Left", current),
          const SizedBox(width: 8),
          _positionOption(
              WatermarkPosition.bottomRight, "Bottom Right", current),
        ],
      ),
    );
  }

  Widget _positionOption(
      WatermarkPosition pos, String label, WatermarkPosition current) {
    final isSelected = pos == current;
    return Expanded(
      child: InkWell(
        onTap: () {
          final overlay = ref.read(overlayPreviewProvider);
          ref.read(overlayPreviewProvider.notifier).state =
              overlay.copyWith(position: pos);
        },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blueAccent : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                        color: Colors.blueAccent.withOpacity(0.3),
                        blurRadius: 10)
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white54,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentNotes(List<dynamic> recent) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: recent.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          return ActionChip(
            label: Text(
              recent[i].text.replaceAll(RegExp(r'\s*\r?\n\s*'), '  |  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: () => _useNote(recent[i]),
            backgroundColor: Colors.white,
            labelStyle: const TextStyle(
                color: Colors.black87,
                fontSize: 13,
                fontWeight: FontWeight.w600),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            side: BorderSide.none,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
          );
        },
      ),
    );
  }

  Widget _buildSavedNotesList(List<dynamic> allNotes) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: allNotes.length,
      itemBuilder: (context, i) {
        final note = allNotes[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(14),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            title: Text(
              note.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Colors.redAccent, size: 20),
              onPressed: () =>
                  ref.read(savedNotesProvider.notifier).deleteNote(note.id),
            ),
            onTap: () => _useNote(note),
          ),
        );
      },
    );
  }

  Widget _buildBottomAction(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _submitNote,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
            elevation: 8,
            shadowColor: Colors.blueAccent.withOpacity(0.4),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_rounded),
              SizedBox(width: 12),
              Text("Apply Configuration",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _fetchLocation(BuildContext context) async {
    final overlay = ref.read(overlayPreviewProvider);
    final lat = overlay.latitude;
    final lng = overlay.longitude;

    if (lat == 0.0 && lng == 0.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Waiting for GPS signal..."),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
          child: CircularProgressIndicator(color: Colors.blueAccent)),
    );

    final overlaySettings = ref.read(overlaySettingsProvider);
    final name = await LocationService.getLocationName(lat, lng,
        language: overlaySettings.language);

    if (context.mounted) {
      Navigator.pop(context);
      if (name != null) {
        setState(() => locationController.text = name);
      }
    }
  }

  Future<void> _submitNote() async {
    final value = _composeWatermarkText();
    if (value.isNotEmpty) {
      await ref.read(savedNotesProvider.notifier).addNote(value);
      final overlay = ref.read(overlayPreviewProvider);
      ref.read(overlayPreviewProvider.notifier).state =
          overlay.copyWith(note: value);
    }
    if (mounted) Navigator.pop(context);
  }

  void _useNote(dynamic note) {
    ref.read(savedNotesProvider.notifier).markAsUsed(note);
    setState(() {
      locationController.text = _locationLineFromWatermark(note.text);
      extraNoteController.text = _extraNoteFromWatermark(note.text);
    });
    final overlay = ref.read(overlayPreviewProvider);
    ref.read(overlayPreviewProvider.notifier).state =
        overlay.copyWith(note: note.text);
    Navigator.pop(context);
  }
}
