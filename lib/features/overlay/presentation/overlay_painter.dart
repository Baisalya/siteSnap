import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart' as svg;
import 'package:image/image.dart' as img;
import 'package:vector_graphics/vector_graphics.dart';

import '../../camera/data/CameraState.dart';
import '../domain/overlay_model.dart';
import 'live_overlay_painter.dart';

class WatermarkProcessor {
  static const String assetName = 'Assets/app_logo.svg';

  static void _applyOrientation(
      Canvas canvas,
      DeviceOrientation orientation,
      double w,
      double h,
      ) {
    switch (orientation) {
      case DeviceOrientation.portraitUp:
        break;
      case DeviceOrientation.portraitDown:
        canvas.translate(w, h);
        canvas.rotate(pi);
        break;
      case DeviceOrientation.landscapeLeft:
        canvas.translate(w, 0);
        canvas.rotate(pi / 2);
        break;
      case DeviceOrientation.landscapeRight:
        canvas.translate(0, h);
        canvas.rotate(-pi / 2);
        break;
    }
  }

  static void _undoOrientationForWatermark(
      Canvas canvas,
      DeviceOrientation orientation,
      double w,
      double h,
      ) {
    switch (orientation) {
      case DeviceOrientation.portraitUp:
        break;
      case DeviceOrientation.portraitDown:
        canvas.translate(w, h);
        canvas.rotate(pi);
        break;
      case DeviceOrientation.landscapeLeft:
        canvas.translate(0, h);
        canvas.rotate(-pi / 2);
        break;
      case DeviceOrientation.landscapeRight:
        canvas.translate(w, 0);
        canvas.rotate(pi / 2);
        break;
    }
  }

  static Future<Uint8List> drawOverlay(
      File file,
      OverlayData data,
      DeviceOrientation orientation, {
        bool showOverlay = true,
        bool showWatermark = true,
        ui.Image? decodedImage,
        CameraAspectRatio? aspectRatio,
        bool mirror = false,
      }) async {
    final ui.Image uiImage;
    if (decodedImage != null) {
      uiImage = decodedImage;
    } else {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      uiImage = frame.image;
    }

    final svgString = await rootBundle.loadString(assetName);
    final PictureInfo pictureInfo = await svg.vg.loadPicture(
      svg.SvgStringLoader(svgString),
      null,
    );

    final double srcW = uiImage.width.toDouble();
    final double srcH = uiImage.height.toDouble();

    Rect srcRect = Rect.fromLTWH(0, 0, srcW, srcH);

    if (aspectRatio != null) {
      final double targetRatio =
      aspectRatio == CameraAspectRatio.ratio4_3 ? 3 / 4 : 9 / 16;
      final double currentRatio = srcW / srcH;

      if (currentRatio > targetRatio) {
        final double newW = srcH * targetRatio;
        srcRect = Rect.fromCenter(
          center: Offset(srcW / 2, srcH / 2),
          width: newW,
          height: srcH,
        );
      } else if (currentRatio < targetRatio) {
        final double newH = srcW / targetRatio;
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
    _applyOrientation(canvas, orientation, dstW, dstH);

    // Draw image
    if (mirror) {
      canvas.save();
      canvas.translate(srcRect.width, 0);
      canvas.scale(-1, 1);
      canvas.drawImageRect(
        uiImage,
        srcRect,
        Rect.fromLTWH(0, 0, srcRect.width, srcRect.height),
        Paint()..filterQuality = ui.FilterQuality.high,
      );
      canvas.restore();
    } else {
      canvas.drawImageRect(
        uiImage,
        srcRect,
        Rect.fromLTWH(0, 0, srcRect.width, srcRect.height),
        Paint()..filterQuality = ui.FilterQuality.high,
      );
    }

    // Overlay
    if (showOverlay) {
      final overlayPainter = LiveOverlayPainter(data, orientation);
      overlayPainter.paint(
        canvas,
        Size(srcRect.width, srcRect.height),
      );
    }

    // ================= WATERMARK =================
    if (showWatermark) {
      canvas.save();

      _undoOrientationForWatermark(
        canvas,
        orientation,
        srcRect.width,
        srcRect.height,
      );

      final double contentW = srcRect.width;
      final double baseSize = min(srcRect.width, srcRect.height);
      final double padding = contentW * 0.04;

      final textPainter = TextPainter(
        text: TextSpan(
          text: "SurveyCam",
          style: TextStyle(
            color: Colors.white,
            fontSize: baseSize * 0.045,
            fontWeight: FontWeight.bold,
            shadows: const [
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

      final double svgSize = textPainter.height;
      const double spacing = 10;
      final double totalWidth = svgSize + spacing + textPainter.width;

      /// ✅ FIXED POSITION LOGIC
      final bool isLandscape =
          orientation == DeviceOrientation.landscapeLeft ||
              orientation == DeviceOrientation.landscapeRight;

      final double dx = isLandscape
          ? padding // landscape → left
          : contentW - totalWidth - padding; // portrait → right

      final double dy = padding;

      // Draw SVG
      canvas.save();
      canvas.translate(dx, dy);

      final double scale = svgSize / pictureInfo.size.height;
      canvas.scale(scale, scale);
      canvas.drawPicture(pictureInfo.picture);

      canvas.restore();

      // Draw Text
      textPainter.paint(
        canvas,
        Offset(dx + svgSize + spacing, dy),
      );

      canvas.restore();
    }

    canvas.restore();

    final picture = recorder.endRecording();
    final finalImage = await picture.toImage(dstW.toInt(), dstH.toInt());

    final byteData =
    await finalImage.toByteData(format: ui.ImageByteFormat.rawRgba);

    if (byteData == null) return Uint8List(0);

    final processedImage = img.Image.fromBytes(
      width: finalImage.width,
      height: finalImage.height,
      bytes: byteData.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );

    return Uint8List.fromList(
      img.encodeJpg(processedImage, quality: 100),
    );
  }
}