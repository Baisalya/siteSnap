import 'dart:io';
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
  /// 1️⃣ LOAD ORIGINAL IMAGE
  /// ===============================
  final bytes = await file.readAsBytes();

  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final uiImage = frame.image;

  final width = uiImage.width.toDouble();
  final height = uiImage.height.toDouble();

  /// ===============================
  /// 2️⃣ CREATE CANVAS
  /// ===============================
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  /// draw original image first
  final paint = Paint();
  canvas.drawImage(uiImage, Offset.zero, paint);

  /// ===============================
  /// 3️⃣ DRAW SAME OVERLAY AS CAMERA
  /// ===============================
  final overlayPainter =
  LiveOverlayPainter(data, orientation);

  overlayPainter.paint(canvas, Size(width, height));

  /// ===============================
  /// 4️⃣ EXPORT TO IMAGE
  /// ===============================
  final picture = recorder.endRecording();
  final finalImage =
  await picture.toImage(uiImage.width, uiImage.height);

  final byteData =
  await finalImage.toByteData(format: ui.ImageByteFormat.png);

  final newFile =
  await file.writeAsBytes(byteData!.buffer.asUint8List());

  return newFile;
}
