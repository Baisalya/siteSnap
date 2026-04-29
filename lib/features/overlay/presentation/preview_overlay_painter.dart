import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart' as svg;
import 'package:vector_graphics/vector_graphics.dart';

import 'package:surveycam/features/overlay/domain/WatermarkPosition.dart';
import 'package:surveycam/features/overlay/domain/overlay_model.dart';
import 'package:surveycam/features/overlay/domain/overlay_settings.dart';
import 'package:surveycam/features/overlay/presentation/live_overlay_painter.dart';

class PreviewOverlayPainter extends CustomPainter {
  final OverlayData data;
  final bool showOverlay;
  final bool showWatermark;
  final DeviceOrientation orientation;
  final OverlaySettings settings;

  /// ✅ Preloaded SVG
  final PictureInfo? svgPicture;

  PreviewOverlayPainter({
    required this.data,
    required this.showOverlay,
    required this.showWatermark,
    required this.orientation,
    required this.svgPicture,
    this.settings = const OverlaySettings(),
  });

  /// ✅ Load SVG once before using painter
  static Future<PictureInfo> loadSvg() async {
    const assetName = 'Assets/app_logo.svg';

    final svgString = await rootBundle.loadString(assetName);
    return await svg.vg.loadPicture(
      svg.SvgStringLoader(svgString),
      null,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width == 0 || size.height == 0) return;

    /// 📍 MAIN OVERLAY
    if (showOverlay) {
      final painter = LiveOverlayPainter(data, orientation, settings: settings);
      painter.paint(canvas, size);
    }

    /// 📍 WATERMARK
    if (showWatermark && svgPicture != null) {
      _drawWatermark(canvas, size);
    }
  }

  void _drawWatermark(Canvas canvas, Size size) {
    canvas.save();

    // ===============================
    // ROTATION (same as before)
    // ===============================
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

    double drawWidth = size.width;
    double drawHeight = size.height;

    if (orientation == DeviceOrientation.landscapeLeft ||
        orientation == DeviceOrientation.landscapeRight) {
      drawWidth = size.height;
      drawHeight = size.width;
    }

    final baseSize = min(drawWidth, drawHeight);

    // ===============================
    // TEXT
    // ===============================
    final textPainter = TextPainter(
      text: TextSpan(
        text: "SurveyCam",
        style: TextStyle(
          color: Colors.white,
          fontSize: baseSize * 0.045,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              blurRadius: 4,
              color: Colors.black.withOpacity(0.5),
              offset: const Offset(1, 1),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final padding = drawWidth * 0.04;
    const spacing = 8.0;

    // ===============================
    // SVG SIZE
    // ===============================
    final svgSize = textPainter.height;
    final totalWidth = svgSize + spacing + textPainter.width;

    // ===============================
    // POSITION (UNCHANGED)
    // ===============================
    final isRightSide = data.position != WatermarkPosition.bottomLeft;

    final dx = isRightSide
        ? drawWidth - totalWidth - padding
        : padding;

    final dy = padding;

    // ===============================
    // DRAW SVG
    // ===============================
    canvas.save();
    canvas.translate(dx, dy);

    final scale = svgSize / svgPicture!.size.height;
    canvas.scale(scale, scale);
    canvas.drawPicture(svgPicture!.picture);
    canvas.restore();

    // ===============================
    // DRAW TEXT
    // ===============================
    textPainter.paint(
      canvas,
      Offset(dx + svgSize + spacing, dy),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PreviewOverlayPainter oldDelegate) {
    return oldDelegate.showOverlay != showOverlay ||
        oldDelegate.showWatermark != showWatermark ||
        oldDelegate.data != data ||
        oldDelegate.orientation != orientation ||
        oldDelegate.svgPicture != svgPicture ||
        oldDelegate.settings != settings;
  }
}