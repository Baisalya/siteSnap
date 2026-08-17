double zoomForGesture({
  required double startZoom,
  required double scale,
  required double minZoom,
  required double maxZoom,
}) {
  return (startZoom * scale).clamp(minZoom, maxZoom).toDouble();
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
