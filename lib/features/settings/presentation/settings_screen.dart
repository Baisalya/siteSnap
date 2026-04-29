import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:surveycam/features/overlay/presentation/overlay_settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(overlaySettingsProvider);
    final notifier = ref.read(overlaySettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Overlay Settings'),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Appearance',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            title: const Text('Background Color'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _colorCircle((c) => notifier.setBackgroundColor(c), Colors.white, settings.backgroundColor == Colors.white),
                _colorCircle((c) => notifier.setBackgroundColor(c), Colors.black, settings.backgroundColor == Colors.black),
                _colorCircle((c) => notifier.setBackgroundColor(c), const Color(0xFF1976D2), settings.backgroundColor == const Color(0xFF1976D2)),
                _colorCircle((c) => notifier.setBackgroundColor(c), const Color(0xFF388E3C), settings.backgroundColor == const Color(0xFF388E3C)),
              ],
            ),
          ),
          ListTile(
            title: const Text('Text Color'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _colorCircle((c) => notifier.setTextColor(c), Colors.white, settings.textColor == Colors.white),
                _colorCircle((c) => notifier.setTextColor(c), Colors.black, settings.textColor == Colors.black),
                _colorCircle((c) => notifier.setTextColor(c), Colors.blue.shade100, settings.textColor == Colors.blue.shade100),
                _colorCircle((c) => notifier.setTextColor(c), Colors.green.shade100, settings.textColor == Colors.green.shade100),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Background Opacity'),
                Slider(
                  value: settings.backgroundOpacity,
                  min: 0.0,
                  max: 1.0,
                  divisions: 10,
                  label: '${(settings.backgroundOpacity * 100).toInt()}%',
                  onChanged: (value) => notifier.setBackgroundOpacity(value),
                ),
              ],
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Visible Elements',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          SwitchListTile(
            title: const Text('Date & Time'),
            value: settings.showDateTime,
            onChanged: (value) => notifier.setShowDateTime(value),
          ),
          SwitchListTile(
            title: const Text('Coordinates (Lat/Long)'),
            value: settings.showCoordinates,
            onChanged: (value) => notifier.setShowCoordinates(value),
          ),
          SwitchListTile(
            title: const Text('Altitude'),
            value: settings.showAltitude,
            onChanged: (value) => notifier.setShowAltitude(value),
          ),
          SwitchListTile(
            title: const Text('Direction & Heading'),
            value: settings.showDirection,
            onChanged: (value) => notifier.setShowDirection(value),
          ),
          SwitchListTile(
            title: const Text('Note/Address'),
            value: settings.showNote,
            onChanged: (value) => notifier.setShowNote(value),
          ),
          /*
          SwitchListTile(
            title: const Text('Weather (Experimental)'),
            value: settings.showWeather,
            onChanged: (value) => notifier.setShowWeather(value),
          ),
          SwitchListTile(
            title: const Text('Humidity (Experimental)'),
            value: settings.showHumidity,
            onChanged: (value) => notifier.setShowHumidity(value),
          ),
          SwitchListTile(
            title: const Text('Air Quality (Experimental)'),
            value: settings.showAir,
            onChanged: (value) => notifier.setShowAir(value),
          ),
          */
        ],
      ),
    );
  }

  Widget _colorCircle(Function(Color) onTap, Color color, bool isSelected) {
    return GestureDetector(
      onTap: () => onTap(color),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey,
            width: isSelected ? 3 : 1,
          ),
        ),
      ),
    );
  }
}
