import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:surveycam/core/services/location_service.dart';
import 'package:surveycam/features/overlay/domain/WatermarkPosition.dart';
import 'package:surveycam/features/overlay/presentation/overlay_preview_state.dart';
import 'package:surveycam/features/overlay/presentation/overlay_settings_provider.dart';
import 'package:surveycam/features/overlay/presentation/saved_notes_provider.dart';

import 'camera_settings_provider.dart';

class NoteInputSheet extends ConsumerStatefulWidget {
  const NoteInputSheet({super.key});

  @override
  ConsumerState<NoteInputSheet> createState() => _NoteInputSheetState();
}

class _NoteInputSheetState extends ConsumerState<NoteInputSheet> {
  late TextEditingController controller;

  @override
  void initState() {
    super.initState();
    // Initialize with current note if exists
    final currentNote = ref.read(overlayPreviewProvider).note;
    controller = TextEditingController(text: currentNote);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(savedNotesProvider);
    final overlaySettings = ref.watch(overlaySettingsProvider);
    final settingsNotifier = ref.read(overlaySettingsProvider.notifier);
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
          _buildHeader(context, settingsNotifier),

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

                  // ───── APPEARANCE & CONTENT (EXPANDABLE) ─────
                  _buildAppearanceCard(context, overlaySettings, settingsNotifier),

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
                        Text("${allNotes.length} total", style: const TextStyle(color: Colors.white24, fontSize: 11)),
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

  Widget _buildHeader(BuildContext context, dynamic settingsNotifier) {
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
                const Icon(Icons.layers_outlined, color: Colors.blueAccent, size: 22),
                const SizedBox(width: 12),
                const Text(
                  "Overlay Configuration",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => settingsNotifier.resetToDefaults(),
                  icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.blueAccent),
                  label: const Text("Reset", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
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

  Widget _buildSearchInput(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        decoration: InputDecoration(
          hintText: 'Enter project name or location...',
          hintStyle: const TextStyle(color: Colors.white24),
          prefixIcon: const Icon(Icons.edit_note_rounded, color: Colors.blueAccent, size: 24),
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
          border: InputBorder.none,
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (controller.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white24, size: 20),
                  onPressed: () => setState(() => controller.clear()),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton(
                  icon: const Icon(Icons.my_location_rounded, color: Colors.blueAccent),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.blueAccent.withOpacity(0.1),
                  ),
                  onPressed: () => _fetchLocation(context),
                ),
              ),
            ],
          ),
        ),
        onChanged: (val) => setState(() {}),
        onSubmitted: (text) => _submitNote(text),
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
          _positionOption(WatermarkPosition.bottomRight, "Bottom Right", current),
        ],
      ),
    );
  }

  Widget _positionOption(WatermarkPosition pos, String label, WatermarkPosition current) {
    final isSelected = pos == current;
    return Expanded(
      child: InkWell(
        onTap: () {
          final overlay = ref.read(overlayPreviewProvider);
          ref.read(overlayPreviewProvider.notifier).state = overlay.copyWith(position: pos);
        },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blueAccent : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected ? [BoxShadow(color: Colors.blueAccent.withOpacity(0.3), blurRadius: 10)] : null,
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

  Widget _buildAppearanceCard(BuildContext context, dynamic settings, dynamic notifier) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const PageStorageKey('appearance_tile'),
          leading: const Icon(Icons.tune_rounded, color: Colors.blueAccent),
          title: const Text("Overlay Settings", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          subtitle: const Text("Visual appearance & visible info", style: TextStyle(color: Colors.white38, fontSize: 12)),
          trailing: const Icon(Icons.expand_more_rounded, color: Colors.white24),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            const Divider(color: Colors.white10),
            const SizedBox(height: 16),
            _buildSectionLabel("VISUAL STYLE"),
            const SizedBox(height: 16),
            _buildSliderRow("Background Opacity", settings.backgroundOpacity, (v) => notifier.setBackgroundOpacity(v)),
            const SizedBox(height: 20),
            _buildColorRow("Background Color", (c) => notifier.setBackgroundColor(c), settings.backgroundColor, [
              Colors.white, Colors.black, const Color(0xFF1976D2), const Color(0xFF2E7D32),
            ]),
            const SizedBox(height: 20),
            _buildColorRow("Text Color", (c) => notifier.setTextColor(c), settings.textColor, [
              Colors.white, Colors.black, Colors.yellow.shade100, Colors.blue.shade100,
            ]),
            const SizedBox(height: 24),
            const Divider(color: Colors.white10),
            const SizedBox(height: 16),
            _buildSectionLabel("VISIBLE INFORMATION"),
            const SizedBox(height: 16),
            _buildDataToggles(settings, notifier),
            const SizedBox(height: 16),
            _buildAutoFetchToggle(),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderRow(String label, double value, Function(double) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            Text("${(value * 100).toInt()}%", style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7, elevation: 3),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            activeTrackColor: Colors.blueAccent,
            inactiveTrackColor: Colors.white10,
          ),
          child: Slider(
            value: value,
            onChanged: onChanged,
            divisions: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildColorRow(String label, Function(Color) onSelect, Color current, List<Color> options) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: options.map((c) => _colorOption(onSelect, c, current == c)).toList(),
        ),
      ],
    );
  }

  Widget _colorOption(Function(Color) onTap, Color color, bool isSelected) {
    return GestureDetector(
      onTap: () => onTap(color),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.blueAccent : Colors.white10,
            width: isSelected ? 3 : 1,
          ),
          boxShadow: isSelected ? [BoxShadow(color: Colors.blueAccent.withOpacity(0.4), blurRadius: 10)] : null,
        ),
        child: isSelected ? const Icon(Icons.check_rounded, color: Colors.blueAccent, size: 24) : null,
      ),
    );
  }

  Widget _buildDataToggles(dynamic settings, dynamic notifier) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _toggleChip("Date & Time", Icons.calendar_today_rounded, settings.showDateTime, (v) => notifier.setShowDateTime(v)),
        _toggleChip("Coordinates", Icons.gps_fixed_rounded, settings.showCoordinates, (v) => notifier.setShowCoordinates(v)),
        _toggleChip("Altitude", Icons.height_rounded, settings.showAltitude, (v) => notifier.setShowAltitude(v)),
        _toggleChip("Compass", Icons.explore_rounded, settings.showDirection, (v) => notifier.setShowDirection(v)),
        _toggleChip("Address/Note", Icons.notes_rounded, settings.showNote, (v) => notifier.setShowNote(v)),
      ],
    );
  }

  Widget _toggleChip(String label, IconData icon, bool selected, Function(bool) onToggle) {
    return FilterChip(
      showCheckmark: false,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      avatar: Icon(icon, size: 16, color: selected ? Colors.white : Colors.black87),
      label: Text(label),
      selected: selected,
      onSelected: onToggle,
      backgroundColor: Colors.white,
      selectedColor: Colors.blueAccent,
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.black87,
        fontSize: 12,
        fontWeight: selected ? FontWeight.bold : FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      side: BorderSide.none,
    );
  }

  Widget _buildAutoFetchToggle() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueAccent.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueAccent.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_rounded, color: Colors.blueAccent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Intelligent Location", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                Text("Update address automatically as you move", style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
              ],
            ),
          ),
          Switch(
            value: ref.watch(cameraSettingsProvider).autoFetchLocation,
            activeColor: Colors.blueAccent,
            onChanged: (v) => ref.read(cameraSettingsProvider.notifier).setAutoFetchLocation(v),
          ),
        ],
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
            label: Text(recent[i].text),
            onPressed: () => _useNote(recent[i]),
            backgroundColor: Colors.white,
            labelStyle: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w600),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            title: Text(note.text, style: const TextStyle(color: Colors.white, fontSize: 14)),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
              onPressed: () => ref.read(savedNotesProvider.notifier).deleteNote(note.id),
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
          onPressed: () => _submitNote(controller.text),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
            elevation: 8,
            shadowColor: Colors.blueAccent.withOpacity(0.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_rounded),
              SizedBox(width: 12),
              Text("Apply Configuration", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.blueAccent)),
    );

    final name = await LocationService.getLocationName(lat, lng);

    if (context.mounted) {
      Navigator.pop(context);
      if (name != null) {
        setState(() => controller.text = name);
      }
    }
  }

  Future<void> _submitNote(String text) async {
    final value = text.trim();
    if (value.isNotEmpty) {
      await ref.read(savedNotesProvider.notifier).addNote(value);
      final overlay = ref.read(overlayPreviewProvider);
      ref.read(overlayPreviewProvider.notifier).state = overlay.copyWith(note: value);
    }
    if (mounted) Navigator.pop(context);
  }

  void _useNote(dynamic note) {
    ref.read(savedNotesProvider.notifier).markAsUsed(note);
    final overlay = ref.read(overlayPreviewProvider);
    ref.read(overlayPreviewProvider.notifier).state = overlay.copyWith(note: note.text);
    Navigator.pop(context);
  }
}
