double zoomForGesture({
  required double startZoom,
  required double scale,
  required double minZoom,
  required double maxZoom,
}) {
  return (startZoom * scale).clamp(minZoom, maxZoom).toDouble();
}

double zoomForScaleDelta({
  required double currentZoom,
  required double previousScale,
  required double currentScale,
  required double minZoom,
  required double maxZoom,
}) {
  if (!currentZoom.isFinite ||
      !previousScale.isFinite ||
      !currentScale.isFinite ||
      previousScale <= 0 ||
      currentScale <= 0) {
    return currentZoom.clamp(minZoom, maxZoom).toDouble();
  }

  final scaleDelta = currentScale / previousScale;
  return (currentZoom * scaleDelta).clamp(minZoom, maxZoom).toDouble();
}

String formatRecordingDuration(Duration elapsed) {
  final totalSeconds = elapsed.inSeconds.clamp(0, 359999);
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final minuteText = minutes.toString().padLeft(2, '0');
  final secondText = seconds.toString().padLeft(2, '0');

  if (hours == 0) {
    return '$minuteText:$secondText';
  }

  return '${hours.toString().padLeft(2, '0')}:$minuteText:$secondText';
}
