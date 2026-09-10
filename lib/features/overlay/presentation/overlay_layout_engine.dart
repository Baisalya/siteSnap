import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:surveycam/core/utils/overlay_utils.dart';
import 'package:surveycam/features/overlay/domain/WatermarkPosition.dart';
import 'package:surveycam/features/overlay/domain/overlay_render_snapshot.dart';

/// Geometry helpers shared by live preview and encoded-frame rendering.
class OverlayFrameGeometry {
  const OverlayFrameGeometry._();

  static bool shouldRotateForFrame({
    required Size frameSize,
    required DeviceOrientation orientation,
  }) {
    final frameIsLandscape = frameSize.width > frameSize.height;
    final overlayIsLandscape = orientation == DeviceOrientation.landscapeLeft ||
        orientation == DeviceOrientation.landscapeRight;
    return frameIsLandscape != overlayIsLandscape;
  }

  /// Converts device orientation into the orientation that should be painted
  /// on a frame whose pixels may already have been normalized by the recorder.
  static DeviceOrientation orientationForEncodedFrame({
    required Size frameSize,
    required DeviceOrientation orientation,
  }) {
    final isFrameLandscape = frameSize.width > frameSize.height;
    if (!isFrameLandscape) return orientation;

    switch (orientation) {
      case DeviceOrientation.landscapeLeft:
      case DeviceOrientation.landscapeRight:
        return DeviceOrientation.portraitUp;
      case DeviceOrientation.portraitUp:
        return DeviceOrientation.landscapeLeft;
      case DeviceOrientation.portraitDown:
        return DeviceOrientation.landscapeRight;
    }
  }

  static Size logicalSizeForOrientation(
    Size size,
    DeviceOrientation orientation,
  ) {
    if (orientation == DeviceOrientation.landscapeLeft ||
        orientation == DeviceOrientation.landscapeRight) {
      return Size(size.height, size.width);
    }
    return size;
  }

  static void applyOrientationTransform(
    Canvas canvas,
    Size size,
    DeviceOrientation orientation,
  ) {
    switch (orientation) {
      case DeviceOrientation.portraitUp:
        break;
      case DeviceOrientation.portraitDown:
        canvas.translate(size.width, size.height);
        canvas.rotate(pi);
        break;
      case DeviceOrientation.landscapeLeft:
        canvas.translate(0, size.height);
        canvas.rotate(-pi / 2);
        break;
      case DeviceOrientation.landscapeRight:
        canvas.translate(size.width, 0);
        canvas.rotate(pi / 2);
        break;
    }
  }
}

/// Single source of truth for the information card shown on camera preview,
/// still images and video overlay frames.
class OverlayCardRenderer {
  const OverlayCardRenderer._();

  static void paint({
    required Canvas canvas,
    required Size size,
    required OverlayRenderSnapshot snapshot,
  }) {
    if (size.width <= 0 || size.height <= 0) return;

    canvas.save();
    OverlayFrameGeometry.applyOrientationTransform(
      canvas,
      size,
      snapshot.orientation,
    );

    final logicalSize = OverlayFrameGeometry.logicalSizeForOrientation(
      size,
      snapshot.orientation,
    );
    final baseSize = min(logicalSize.width, logicalSize.height);
    final data = snapshot.data;
    final settings = snapshot.settings;

    final textStyle = TextStyle(
      color: settings.textColor,
      fontSize: baseSize * 0.032,
      fontWeight: FontWeight.w600,
      height: 1.2,
      letterSpacing: 0.2,
    );
    final warningStyle = textStyle.copyWith(color: Colors.redAccent);
    final noteStyle = textStyle.copyWith(
      fontSize: baseSize * 0.035,
      color: settings.textColor,
      fontStyle: FontStyle.italic,
    );

    final spans = <TextSpan>[];
    final noteLines = settings.showNote && data.note.trim().isNotEmpty
        ? data.note.trim().split(RegExp(r'\r?\n'))
        : const <String>[];
    final placeLine = noteLines.isEmpty ? '' : noteLines.first.trim();
    final extraNote =
        noteLines.length <= 1 ? '' : noteLines.skip(1).join('\n').trim();

    if (placeLine.isNotEmpty) {
      spans.add(TextSpan(text: '$placeLine\n', style: noteStyle));
    } else if (extraNote.isNotEmpty) {
      // Preserve the visual Line 1 slot used by the live overlay.
      spans.add(TextSpan(text: '\n', style: noteStyle));
    }

    if (settings.showDateTime && data.dateTime.isNotEmpty) {
      spans.add(TextSpan(text: '${data.dateTime}\n', style: textStyle));
    }

    if (settings.showCoordinates) {
      if (data.locationWarning != null) {
        spans.add(TextSpan(
          text: '${data.locationWarning}\n',
          style: warningStyle,
        ));
      } else {
        final latLabel = OverlayUtils.getLabel('latitude', settings.language);
        final lonLabel = OverlayUtils.getLabel('longitude', settings.language);
        final latVal = OverlayUtils.formatCoordinate(
          data.latitude,
          true,
          settings.coordinateFormat,
        );
        final lonVal = OverlayUtils.formatCoordinate(
          data.longitude,
          false,
          settings.coordinateFormat,
        );
        spans.add(TextSpan(
          text: '$latLabel: $latVal\n$lonLabel: $lonVal\n',
          style: textStyle,
        ));
      }
    }

    var altitudeDirection = '';
    if (settings.showAltitude) {
      final label = OverlayUtils.getLabel('altitude', settings.language);
      altitudeDirection += '$label: ${data.altitude.toStringAsFixed(1)}m  ';
    }
    if (settings.showDirection) {
      final label = OverlayUtils.getLabel('direction', settings.language);
      altitudeDirection +=
          '$label: ${data.direction} ${data.heading.toStringAsFixed(0)}°';
    }
    if (altitudeDirection.isNotEmpty) {
      spans.add(TextSpan(text: '$altitudeDirection\n', style: textStyle));
    }

    if (settings.showWeather && data.weather != null) {
      final label = OverlayUtils.getLabel('weather', settings.language);
      spans.add(TextSpan(text: '$label: ${data.weather}\n', style: textStyle));
    }
    if (settings.showHumidity && data.humidity != null) {
      final label = OverlayUtils.getLabel('humidity', settings.language);
      spans.add(TextSpan(text: '$label: ${data.humidity}\n', style: textStyle));
    }
    if (settings.showPressure && data.pressure != null) {
      final label = OverlayUtils.getLabel('pressure', settings.language);
      spans.add(TextSpan(text: '$label: ${data.pressure}\n', style: textStyle));
    }
    if (settings.showAir && data.air != null) {
      final label = OverlayUtils.getLabel('air', settings.language);
      spans.add(TextSpan(text: '$label: ${data.air}\n', style: textStyle));
    }
    if (extraNote.isNotEmpty) {
      spans.add(TextSpan(text: extraNote, style: noteStyle));
    }

    if (spans.isEmpty) {
      canvas.restore();
      return;
    }

    final textPainter = TextPainter(
      text: TextSpan(children: spans),
      textDirection: TextDirection.ltr,
      maxLines: 14,
      ellipsis: '...',
    )..layout(maxWidth: baseSize * 0.75);

    final paddingH = baseSize * 0.03;
    final paddingV = baseSize * 0.02;
    final boxWidth = textPainter.width + (paddingH * 2);
    final boxHeight = textPainter.height + (paddingV * 2);

    final dx = data.position == WatermarkPosition.bottomLeft
        ? 0.0
        : logicalSize.width - boxWidth;
    final dy = logicalSize.height - boxHeight;
    final boxRect = Rect.fromLTWH(dx, dy, boxWidth, boxHeight);

    canvas.drawRRect(
      RRect.fromRectAndRadius(boxRect, const Radius.circular(8)),
      Paint()
        ..color = settings.backgroundColor.withValues(
          alpha: settings.backgroundOpacity,
        ),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(boxRect, const Radius.circular(8)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    textPainter.paint(canvas, Offset(dx + paddingH, dy + paddingV));
    canvas.restore();
  }
}
