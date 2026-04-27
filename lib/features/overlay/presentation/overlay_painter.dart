import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import '../../camera/data/CameraState.dart';

import '../domain/overlay_model.dart';
import 'live_overlay_painter.dart';

Future<Uint8List> drawOverlay(
    File file,
    OverlayData data,
    DeviceOrientation orientation, {
      bool showOverlay = true,
      bool showWatermark = true,
      ui.Image? decodedImage,
      CameraAspectRatio? aspectRatio,
      bool mirror = false,
    }
    ) async {
  /// ===============================
  /// LOAD IMAGE
  /// ===============================
  final ui.Image uiImage;
  if (decodedImage != null) {
    uiImage = decodedImage;
  } else {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    uiImage = frame.image;
  }

  double srcW = uiImage.width.toDouble();
  double srcH = uiImage.height.toDouble();

  // Determine crop area if aspect ratio is provided
  Rect srcRect = Rect.fromLTWH(0, 0, srcW, srcH);
  if (aspectRatio != null) {
    double targetRatio = aspectRatio == CameraAspectRatio.ratio4_3 ? 3 / 4 : 9 / 16;
    
    double currentRatio = srcW / srcH;
    
    if (currentRatio > targetRatio) {
      // Sensor is wider than target ratio -> crop width
      double newW = srcH * targetRatio;
      srcRect = Rect.fromCenter(
        center: Offset(srcW / 2, srcH / 2),
        width: newW,
        height: srcH,
      );
    } else if (currentRatio < targetRatio) {
      // Sensor is taller than target ratio -> crop height
      double newH = srcW / targetRatio;
      srcRect = Rect.fromCenter(
        center: Offset(srcW / 2, srcH / 2),
        width: srcW,
        height: newH,
      );
    }
  }

  double dstW = srcRect.width;
  double dstH = srcRect.height;

  if (orientation == DeviceOrientation.landscapeLeft ||
      orientation == DeviceOrientation.landscapeRight) {
    dstW = srcRect.height;
    dstH = srcRect.width;
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

  /// DRAW IMAGE (Cropped)
  if (mirror) {
    canvas.save();
    canvas.translate(srcRect.width, 0);
    canvas.scale(-1, 1);
    canvas.drawImageRect(
      uiImage,
      srcRect,
      Rect.fromLTWH(0, 0, srcRect.width, srcRect.height),
      Paint()..filterQuality = ui.FilterQuality.high
    );
    canvas.restore();
  } else {
    canvas.drawImageRect(
      uiImage,
      srcRect,
      Rect.fromLTWH(0, 0, srcRect.width, srcRect.height),
      Paint()..filterQuality = ui.FilterQuality.high
    );
  }

  /// DRAW MAIN OVERLAY
  final overlayPainter = LiveOverlayPainter(data, orientation);
  if (showOverlay) {
    overlayPainter.paint(canvas, Size(srcRect.width, srcRect.height));
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
      canvas.translate(srcRect.width, srcRect.height);
      canvas.rotate(pi);
      break;

    case DeviceOrientation.landscapeLeft:
      canvas.translate(0, srcRect.height);
      canvas.rotate(-pi / 2);
      break;

    case DeviceOrientation.landscapeRight:
      canvas.translate(srcRect.width, 0);
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
  /// PLACE WATERMARK (SAME SIDE, OTHER CORNER)
  /// ===============================
  late Offset offset;

  if (isRightSide) {
    /// Bottom Right → Top Right
    offset = Offset(
      dstW - textPainter.width - padding,
      padding,
    );
  } else {
    /// Bottom Left → Top Left
    offset = Offset(
      padding,
      padding,
    );
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

  final byteData = await finalImage.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );

  if (byteData == null) return Uint8List(0);

  // Convert raw RGBA bytes to JPEG using the 'image' library
  final image = img.Image.fromBytes(
    width: finalImage.width,
    height: finalImage.height,
    bytes: byteData.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );

  return Uint8List.fromList(img.encodeJpg(image, quality: 100));
}