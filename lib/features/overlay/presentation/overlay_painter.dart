import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart' as svg;
import 'package:image/image.dart' as img;
import 'package:vector_graphics/vector_graphics.dart';

import 'package:surveycam/features/camera/data/CameraState.dart';
import 'package:surveycam/features/overlay/domain/overlay_model.dart';
import 'package:surveycam/features/overlay/domain/overlay_settings.dart';
import 'package:surveycam/features/overlay/presentation/live_overlay_painter.dart';

class WatermarkProcessor {
  static const String assetName = 'Assets/app_logo.svg';
  static String? _cachedSvgString;

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
    CameraAspectRatio? aspectRatio,
    bool mirror = false,
    OverlaySettings settings = const OverlaySettings(),
  }) async {
    final ui.Image uiImage;
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    uiImage = frame.image;

    _cachedSvgString ??= await rootBundle.loadString(assetName);
    final PictureInfo pictureInfo = await svg.vg.loadPicture(
      svg.SvgStringLoader(_cachedSvgString!),
      null,
    );
    final customLogo = await _loadCustomLogo(settings.activeWatermarkLogoPath);

    final double srcW = uiImage.width.toDouble();
    final double srcH = uiImage.height.toDouble();

    Rect srcRect = Rect.fromLTWH(0, 0, srcW, srcH);

    if (aspectRatio != null) {
      final double targetRatio = aspectRatio.portraitValue;
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
      final overlayPainter =
          LiveOverlayPainter(data, orientation, settings: settings);
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

      final brandText = settings.activeWatermarkText.trim();
      final hasText = brandText.isNotEmpty;
      final hasLogo = settings.activeWatermarkShowLogo;
      final textPainter = _brandTextPainter(brandText, baseSize);
      final double logoSize =
          hasLogo ? (hasText ? textPainter.height : baseSize * 0.06) : 0;
      final double spacing = hasLogo && hasText ? 10 : 0;
      final double totalWidth =
          logoSize + spacing + (hasText ? textPainter.width : 0);

      /// ✅ RESTORED OLD POSITION LOGIC FOR PHOTOS
      final bool isLandscape = orientation == DeviceOrientation.landscapeLeft ||
          orientation == DeviceOrientation.landscapeRight;

      final double dx = isLandscape
          ? padding // landscape → left
          : contentW - totalWidth - padding; // portrait → right

      final double dy = padding;

      if (totalWidth > 0) {
        if (hasLogo) {
          _paintBrandLogo(
            canvas: canvas,
            offset: Offset(dx, dy),
            size: logoSize,
            defaultLogo: pictureInfo,
            customLogo: customLogo,
          );
        }
        if (hasText) {
          textPainter.paint(canvas, Offset(dx + logoSize + spacing, dy));
        }
      }

      canvas.restore();
    }

    canvas.restore();

    final picture = recorder.endRecording();
    final finalImage = await picture.toImage(dstW.toInt(), dstH.toInt());
    final finalWidth = finalImage.width;
    final finalHeight = finalImage.height;

    final byteData =
        await finalImage.toByteData(format: ui.ImageByteFormat.rawRgba);

    // Dispose UI images as early as possible
    uiImage.dispose();
    finalImage.dispose();
    customLogo?.dispose();

    if (byteData == null) return Uint8List(0);

    debugPrint("Processing Image: ${finalWidth}x$finalHeight");

    return await compute(_encodeJpgTask, {
      'width': finalWidth,
      'height': finalHeight,
      'buffer': byteData.buffer,
    });
  }

  static Future<ui.Image?> _loadCustomLogo(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  static TextPainter _brandTextPainter(String text, double baseSize) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: baseSize * 0.045,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              blurRadius: 6,
              color: Colors.black.withValues(alpha: 0.5),
              offset: const Offset(1, 1),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  static void _paintBrandLogo({
    required Canvas canvas,
    required Offset offset,
    required double size,
    required PictureInfo defaultLogo,
    ui.Image? customLogo,
  }) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);

    if (customLogo != null) {
      canvas.drawImageRect(
        customLogo,
        Rect.fromLTWH(
          0,
          0,
          customLogo.width.toDouble(),
          customLogo.height.toDouble(),
        ),
        Rect.fromLTWH(0, 0, size, size),
        Paint()..filterQuality = ui.FilterQuality.high,
      );
    } else {
      final double scale = size / defaultLogo.size.height;
      canvas.scale(scale, scale);
      canvas.drawPicture(defaultLogo.picture);
    }

    canvas.restore();
  }

  static Uint8List _encodeJpgTask(Map<String, dynamic> params) {
    final int width = params['width'];
    final int height = params['height'];
    final ByteBuffer buffer = params['buffer'];

    final processedImage = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );

    return Uint8List.fromList(
      img.encodeJpg(
        processedImage,
        quality: 100,
        chroma: img
            .JpegChroma.yuv444, // 🔥 No chroma subsampling for maximum clarity
      ),
    );
  }
}
