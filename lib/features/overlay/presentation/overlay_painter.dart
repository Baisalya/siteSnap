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
    DeviceOrientation orientation,
    ) async {
  /// ===============================
  /// 1️⃣ LOAD IMAGE
  /// ===============================
  final bytes = await file.readAsBytes();

  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final uiImage = frame.image;

  double srcW = uiImage.width.toDouble();
  double srcH = uiImage.height.toDouble();

  double dstW = srcW;
  double dstH = srcH;

  // landscape ke liye size swap
  if (orientation == DeviceOrientation.landscapeLeft ||
      orientation == DeviceOrientation.landscapeRight) {
    dstW = srcH;
    dstH = srcW;
  }
  /// ===============================
  /// 2️⃣ CREATE CANVAS
  /// ===============================
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  canvas.save();

  /// ===============================
  /// ROTATE IMAGE LIKE REAL CAMERA
  /// ===============================
  switch (orientation) {

    case DeviceOrientation.portraitUp:
    // no rotation
      break;

    case DeviceOrientation.portraitDown:
      canvas.translate(dstW, dstH);
      canvas.rotate(pi);
      break;

  // ✅ FIXED (SWAPPED)
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
  canvas.drawImage(
    uiImage,
    Offset.zero,
    Paint(),
  );

  /// DRAW OVERLAY
  final overlayPainter =
  LiveOverlayPainter(data, orientation);

  overlayPainter.paint(
    canvas,
    Size(srcW, srcH),
  );

  canvas.restore();

  final picture = recorder.endRecording();

  final finalImage =
  await picture.toImage(dstW.toInt(), dstH.toInt());

  final byteData =
  await finalImage.toByteData(
    format: ui.ImageByteFormat.png,
  );

  final newFile =
  await file.writeAsBytes(byteData!.buffer.asUint8List());

  return newFile;
}
