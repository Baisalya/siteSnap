import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:surveycam/core/services/weather_service.dart';
import 'package:surveycam/features/overlay/domain/overlay_settings.dart';
import 'package:surveycam/features/overlay/presentation/overlay_settings_provider.dart';

import 'camera_settings_provider.dart';

class OverlayConfigurationScreen extends ConsumerStatefulWidget {
  const OverlayConfigurationScreen({super.key});

  @override
  ConsumerState<OverlayConfigurationScreen> createState() =>
      _OverlayConfigurationScreenState();
}

class _OverlayConfigurationScreenState
    extends ConsumerState<OverlayConfigurationScreen> {
  late Future<EnvironmentSensorAvailability> _sensorAvailabilityFuture;

  @override
  void initState() {
    super.initState();
    _sensorAvailabilityFuture = WeatherService.getLocalSensorAvailability();
    _sensorAvailabilityFuture.then(_clearUnsupportedSensorToggles);
  }

  void _clearUnsupportedSensorToggles(
    EnvironmentSensorAvailability availability,
  ) {
    if (!mounted) return;

    final settings = ref.read(overlaySettingsProvider);
    final updated = settings.copyWith(
      showWeather: availability.temperature ? settings.showWeather : false,
      showHumidity: availability.humidity ? settings.showHumidity : false,
      showAir: availability.airQuality ? settings.showAir : false,
      showPressure: availability.pressure ? settings.showPressure : false,
    );

    if (updated.showWeather != settings.showWeather ||
        updated.showHumidity != settings.showHumidity ||
        updated.showAir != settings.showAir ||
        updated.showPressure != settings.showPressure) {
      ref.read(overlaySettingsProvider.notifier).updateSettings(updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(overlaySettingsProvider);
    final notifier = ref.read(overlaySettingsProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text("Overlay Settings"),
        actions: [
          TextButton.icon(
            onPressed: () => notifier.resetToDefaults(),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text("Reset"),
            style: TextButton.styleFrom(foregroundColor: Colors.blueAccent),
          ),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          _buildSectionLabel("LOCALIZATION & UNITS"),
          const SizedBox(height: 12),
          _buildLocalizationUnitsCard(settings, notifier),
          const SizedBox(height: 24),
          _buildSectionLabel("VISUAL APPEARANCE"),
          const SizedBox(height: 12),
          _buildVisualAppearanceCard(settings, notifier),
          const SizedBox(height: 24),
          _buildSectionLabel("VISIBLE INFORMATION"),
          const SizedBox(height: 12),
          _buildVisibleInformationCard(settings, notifier),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.42),
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildLocalizationUnitsCard(
    OverlaySettings settings,
    OverlaySettingsNotifier notifier,
  ) {
    return _buildCard(
      children: [
        _buildSettingRow(
          "App Language",
          DropdownButton<AppLanguage>(
            value: settings.language,
            dropdownColor: const Color(0xFF2A2A2A),
            underline: const SizedBox(),
            style: const TextStyle(
              color: Colors.blueAccent,
              fontWeight: FontWeight.bold,
            ),
            items: AppLanguage.values.map((language) {
              return DropdownMenuItem(
                value: language,
                child: Text(
                  language == AppLanguage.auto
                      ? "AUTOMATIC"
                      : language.name.toUpperCase(),
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) notifier.setLanguage(value);
            },
          ),
        ),
        const Divider(color: Colors.white10),
        _buildSettingRow(
          "Coordinate Format",
          DropdownButton<CoordinateFormat>(
            value: settings.coordinateFormat,
            dropdownColor: const Color(0xFF2A2A2A),
            underline: const SizedBox(),
            style: const TextStyle(
              color: Colors.blueAccent,
              fontWeight: FontWeight.bold,
            ),
            items: CoordinateFormat.values.map((format) {
              return DropdownMenuItem(
                value: format,
                child: Text(
                  format == CoordinateFormat.decimal
                      ? "Decimal"
                      : "DMS (Deg Min Sec)",
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) notifier.setCoordinateFormat(value);
            },
          ),
        ),
        const Divider(color: Colors.white10),
        _buildSettingRow(
          "Use 24-Hour Time",
          Switch(
            value: settings.use24HourTime,
            activeThumbColor: Colors.blueAccent,
            onChanged: notifier.setUse24HourTime,
          ),
        ),
      ],
    );
  }

  Widget _buildVisualAppearanceCard(
    OverlaySettings settings,
    OverlaySettingsNotifier notifier,
  ) {
    return _buildCard(
      children: [
        _buildSliderRow(
          "Background Opacity",
          settings.backgroundOpacity,
          notifier.setBackgroundOpacity,
        ),
        const SizedBox(height: 20),
        _buildColorRow(
          "Background Color",
          notifier.setBackgroundColor,
          settings.backgroundColor,
          [
            Colors.white,
            Colors.black,
            const Color(0xFF1976D2),
            const Color(0xFF2E7D32),
          ],
        ),
        const SizedBox(height: 20),
        _buildColorRow(
          "Text Color",
          notifier.setTextColor,
          settings.textColor,
          [
            Colors.white,
            Colors.black,
            Colors.yellow.shade100,
            Colors.blue.shade100,
          ],
        ),
      ],
    );
  }

  Widget _buildVisibleInformationCard(
    OverlaySettings settings,
    OverlaySettingsNotifier notifier,
  ) {
    return _buildCard(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: _buildDataToggles(settings, notifier),
        ),
        const SizedBox(height: 18),
        _buildAutoFetchToggle(),
        const SizedBox(height: 12),
        _buildMirrorVideoToggle(),
      ],
    );
  }

  Widget _buildSettingRow(String label, Widget trailing) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _buildSliderRow(
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            Text(
              "${(value * 100).toInt()}%",
              style: const TextStyle(
                color: Colors.blueAccent,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 7,
              elevation: 3,
            ),
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

  Widget _buildColorRow(
    String label,
    ValueChanged<Color> onSelect,
    Color current,
    List<Color> options,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: options
              .map((color) => _colorOption(onSelect, color, current == color))
              .toList(),
        ),
      ],
    );
  }

  Widget _colorOption(
    ValueChanged<Color> onTap,
    Color color,
    bool isSelected,
  ) {
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
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.blueAccent.withValues(alpha: 0.4),
                    blurRadius: 10,
                  )
                ]
              : null,
        ),
        child: isSelected
            ? const Icon(
                Icons.check_rounded,
                color: Colors.blueAccent,
                size: 24,
              )
            : null,
      ),
    );
  }

  Widget _buildDataToggles(
    OverlaySettings settings,
    OverlaySettingsNotifier notifier,
  ) {
    return FutureBuilder<EnvironmentSensorAvailability>(
      future: _sensorAvailabilityFuture,
      builder: (context, snapshot) {
        final availability =
            snapshot.data ?? const EnvironmentSensorAvailability();
        final checking = snapshot.connectionState != ConnectionState.done;
        const checkingMessage =
            "SurveyCam is checking your device sensors. Please try again in a moment.";

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _toggleChip(
              "Date & Time",
              Icons.calendar_today_rounded,
              settings.showDateTime,
              notifier.setShowDateTime,
            ),
            _toggleChip(
              "Coordinates",
              Icons.gps_fixed_rounded,
              settings.showCoordinates,
              notifier.setShowCoordinates,
            ),
            _toggleChip(
              "Altitude",
              Icons.height_rounded,
              settings.showAltitude,
              notifier.setShowAltitude,
            ),
            _toggleChip(
              "Compass",
              Icons.explore_rounded,
              settings.showDirection,
              notifier.setShowDirection,
            ),
            _toggleChip(
              "Address/Note",
              Icons.notes_rounded,
              settings.showNote,
              notifier.setShowNote,
            ),
            _toggleChip(
              "Weather",
              Icons.cloud_outlined,
              settings.showWeather,
              notifier.setShowWeather,
              enabled: !checking && availability.temperature,
              unavailableMessage: checking
                  ? checkingMessage
                  : "This device does not have a local ambient temperature sensor. Without an external weather service, SurveyCam cannot add live weather data.",
            ),
            _toggleChip(
              "Humidity",
              Icons.water_drop_outlined,
              settings.showHumidity,
              notifier.setShowHumidity,
              enabled: !checking && availability.humidity,
              unavailableMessage: checking
                  ? checkingMessage
                  : "This device does not have a local humidity sensor. Without an external weather service, SurveyCam cannot add humidity data.",
            ),
            _toggleChip(
              "Air Quality",
              Icons.air_outlined,
              settings.showAir,
              notifier.setShowAir,
              enabled: !checking && availability.airQuality,
              unavailableMessage: checking
                  ? checkingMessage
                  : "Air quality is not available from standard phone sensors. It requires an external air-quality data source, so SurveyCam cannot add it in local-only mode.",
            ),
            _toggleChip(
              "Pressure",
              Icons.speed_outlined,
              settings.showPressure,
              notifier.setShowPressure,
              enabled: !checking && availability.pressure,
              unavailableMessage: checking
                  ? checkingMessage
                  : "This device does not have a local barometer sensor. Without that sensor, SurveyCam cannot add pressure data.",
            ),
          ],
        );
      },
    );
  }

  Widget _toggleChip(
    String label,
    IconData icon,
    bool selected,
    ValueChanged<bool> onToggle, {
    bool enabled = true,
    String? unavailableMessage,
  }) {
    final isSelected = enabled && selected;
    final iconColor = enabled
        ? (isSelected ? Colors.white : Colors.black87)
        : Colors.white.withValues(alpha: 0.38);
    final labelColor = enabled
        ? (isSelected ? Colors.white : Colors.black87)
        : Colors.white.withValues(alpha: 0.48);

    return FilterChip(
      showCheckmark: false,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      avatar: Icon(icon, size: 16, color: iconColor),
      label: Text(label),
      selected: isSelected,
      onSelected: enabled
          ? onToggle
          : (_) => _showUnavailableSensorDialog(
                label,
                unavailableMessage ?? "This device does not support this data.",
              ),
      backgroundColor:
          enabled ? Colors.white : Colors.white.withValues(alpha: 0.08),
      selectedColor: Colors.blueAccent,
      labelStyle: TextStyle(
        color: labelColor,
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      side: enabled
          ? BorderSide.none
          : BorderSide(color: Colors.white.withValues(alpha: 0.08)),
    );
  }

  void _showUnavailableSensorDialog(String label, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F1F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          "$label unavailable",
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoFetchToggle() {
    final settings = ref.watch(cameraSettingsProvider);

    return _buildToggleRow(
      icon: Icons.auto_awesome_rounded,
      iconColor: Colors.blueAccent,
      title: "Intelligent Location",
      subtitle: "Update address automatically as you move",
      value: settings.autoFetchLocation,
      activeColor: Colors.blueAccent,
      onChanged: ref.read(cameraSettingsProvider.notifier).setAutoFetchLocation,
    );
  }

  Widget _buildMirrorVideoToggle() {
    final settings = ref.watch(cameraSettingsProvider);

    return _buildToggleRow(
      icon: Icons.flip_to_front,
      iconColor: Colors.amberAccent,
      title: "Mirror Front Video",
      subtitle: "Mirror the recording for front camera",
      value: settings.mirrorFrontVideo,
      activeColor: Colors.amberAccent,
      onChanged: ref.read(cameraSettingsProvider.notifier).setMirrorFrontVideo,
    );
  }

  Widget _buildToggleRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required Color activeColor,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: iconColor.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.42),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: activeColor,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
