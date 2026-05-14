import 'dart:isolate';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(VideoProcessingTaskHandler());
}

class VideoProcessingTaskHandler extends TaskHandler {
  @override
  void onStart(DateTime timestamp, SendPort? sendPort) async {
    // Minimal shell. Actual processing is orchestrated from the main isolate
    // to avoid MissingPluginException with FFmpeg.
  }

  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) {
    // Not used
  }

  @override
  void onDestroy(DateTime timestamp, SendPort? sendPort) {
    // Service destroyed
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }
}
