import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/overlay_model.dart';
import 'live_overlay_painter.dart';

Future<File> drawOverlay(
    File file,
    OverlayData data,
    DeviceOrientation orientation, {
      bool showOverlay = true,
      bool showWatermark = true,}
    ) async {
  /// ===============================
  /// LOAD IMAGE
  /// ===============================
  final bytes = await file.readAsBytes();

  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final uiImage = frame.image;

  double srcW = uiImage.width.toDouble();
  double srcH = uiImage.height.toDouble();

  double dstW = srcW;
  double dstH = srcH;

  if (orientation == DeviceOrientation.landscapeLeft ||
      orientation == DeviceOrientation.landscapeRight) {
    dstW = srcH;
    dstH = srcW;
  }

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  canvas.save();

  /// ===============================
  /// ROTATE IMAGE
  /// ===============================
  switch (orientation) {
    case DeviceOrientation.portraitUp:
      break;

    case DeviceOrientation.portraitDown:
      canvas.translate(dstW, dstH);
      canvas.rotate(pi);
      break;

    case DeviceOrientation.landscapeLeft:
      canvas.translate(dstW, 0);
      canvas.rotate(pi / 2);
      break;

    case DeviceOrientation.landscapeRight:
      canvas.translate(0, dstH);
      canvas.rotate(-pi / 2);
      break;
  }

  /// DRAW IMAGE
  canvas.drawImage(uiImage, Offset.zero, Paint());

  /// DRAW MAIN OVERLAY
  final overlayPainter = LiveOverlayPainter(data, orientation);
  if (showOverlay) {
    overlayPainter.paint(canvas, Size(srcW, srcH));
  }
  /// ===============================
  /// WATERMARK (AUTO SAME SIDE)
  /// ===============================
  canvas.save();

  /// 🔁 UNDO ROTATION FOR TEXT
  switch (orientation) {
    case DeviceOrientation.portraitUp:
      break;

    case DeviceOrientation.portraitDown:
      canvas.translate(srcW, srcH);
      canvas.rotate(pi);
      break;

    case DeviceOrientation.landscapeLeft:
      canvas.translate(0, srcH);
      canvas.rotate(-pi / 2);
      break;

    case DeviceOrientation.landscapeRight:
      canvas.translate(srcW, 0);
      canvas.rotate(pi / 2);
      break;
  }

  /// ===============================
  /// TEXT STYLE
  /// ===============================
  final textPainter = TextPainter(
    text: const TextSpan(
      text: "SurveyCam",
      style: TextStyle(
        color: Colors.white,
        fontSize: 26,
        fontWeight: FontWeight.bold,
        shadows: [
          Shadow(
            blurRadius: 6,
            color: Colors.black,
            offset: Offset(1, 1),
          ),
        ],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  final padding = dstW * 0.04;

  /// ===============================
  /// DETECT OVERLAY SIDE (LEFT / RIGHT)
  /// ===============================
  final infoText =
      "${data.dateTime}\n"
      "Lat: ${data.latitude.toStringAsFixed(5)}\n"
      "Lng: ${data.longitude.toStringAsFixed(5)}\n"
      "Alt: ${data.altitude.toStringAsFixed(1)} m\n"
      "${data.direction}";

  final infoPainter = TextPainter(
    text: TextSpan(
      text: infoText,
      style: TextStyle(
        color: Colors.white,
        fontSize: dstW * 0.035,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  /// 👉 SAME logic as overlay painter (bottom-right default)
  final infoX = dstW - infoPainter.width - padding;

  final isRightSide = infoX > dstW / 2;

  /// ===============================
  /// DETECT TOP / BOTTOM
  /// ===============================
  /// Your overlay is bottom → so we mark true
  final isBottom = true;

  /// ===============================
  /// PLACE WATERMARK (SAME SIDE, OTHER CORNER)
  /// ===============================
  late Offset offset;

  if (isRightSide) {
    if (isBottom) {
      /// Bottom Right → Top Right
      offset = Offset(
        dstW - textPainter.width - padding,
        padding,
      );
    } else {
      /// Top Right → Bottom Right
      offset = Offset(
        dstW - textPainter.width - padding,
        dstH - textPainter.height - padding,
      );
    }
  } else {
    if (isBottom) {
      /// Bottom Left → Top Left
      offset = Offset(
        padding,
        padding,
      );
    } else {
      /// Top Left → Bottom Left
      offset = Offset(
        padding,
        dstH - textPainter.height - padding,
      );
    }
  }
  if (showOverlay && showWatermark) {
    textPainter.paint(canvas, offset);
  }
  canvas.restore();

  /// ===============================
  /// EXPORT IMAGE
  /// ===============================
  canvas.restore();

  final picture = recorder.endRecording();

  final finalImage =
  await picture.toImage(dstW.toInt(), dstH.toInt());

  final byteData =
  await finalImage.toByteData(
    format: ui.ImageByteFormat.png,
  );

  return await file.writeAsBytes(byteData!.buffer.asUint8List());
}