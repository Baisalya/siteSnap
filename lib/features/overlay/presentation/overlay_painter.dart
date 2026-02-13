import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:native_device_orientation/native_device_orientation.dart';

import '../domain/overlay_model.dart';
import 'live_overlay_painter.dart';

Future<File> drawOverlay(
    File file,
    OverlayData data,
    NativeDeviceOrientation orientation,
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

  /// swap size for landscape output
  if (orientation == NativeDeviceOrientation.landscapeLeft ||
      orientation == NativeDeviceOrientation.landscapeRight) {
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
  /// 3️⃣ ROTATE CANVAS
  /// ===============================
  if (orientation == NativeDeviceOrientation.landscapeLeft) {
    canvas.translate(0, dstH);
    canvas.rotate(-pi / 2);
  }
  else if (orientation == NativeDeviceOrientation.landscapeRight) {
    canvas.translate(dstW, 0);
    canvas.rotate(pi / 2);
  }
  else if (orientation == NativeDeviceOrientation.portraitDown) {
    canvas.translate(dstW, dstH);
    canvas.rotate(pi);
  }


  /// ===============================
  /// 4️⃣ DRAW IMAGE (NO CROPPING)
  /// ===============================
  canvas.drawImageRect(
    uiImage,
    Rect.fromLTWH(0, 0, srcW, srcH),
    Rect.fromLTWH(0, 0, srcW, srcH),
    Paint(),
  );

  /// ===============================
  /// 5️⃣ DRAW OVERLAY
  /// ===============================
  final overlayPainter =
  LiveOverlayPainter(data, orientation);

  overlayPainter.paint(canvas, Size(srcW, srcH));

  canvas.restore();

  /// ===============================
  /// 6️⃣ EXPORT IMAGE
  /// ===============================
  final picture = recorder.endRecording();

  final finalImage =
  await picture.toImage(dstW.toInt(), dstH.toInt());

  final byteData =
  await finalImage.toByteData(format: ui.ImageByteFormat.png);

  final newFile =
  await file.writeAsBytes(byteData!.buffer.asUint8List());

  return newFile;
}
