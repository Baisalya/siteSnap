import 'dart:async';
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
import 'package:ffmpeg_kit_flutter_new_https_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_https_gpl/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_https_gpl/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_https_gpl/statistics.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'package:surveycam/features/overlay/domain/overlay_model.dart';
import 'package:surveycam/features/overlay/domain/overlay_settings.dart';
import 'package:surveycam/features/overlay/domain/video_overlay_sample.dart';
import 'package:surveycam/features/overlay/presentation/live_overlay_painter.dart';

class VideoWatermarkProcessor {
  static const String assetName = 'Assets/app_logo.svg';
  static const double overlaySampleFps = 2.0;
  static const double overlayWidth = 540;
  static const double overlayHeight = 960;

  static void _undoOrientationForVideoWatermark(
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

  static Future<String?> generateVideoOverlaySequence({
    required List<VideoOverlaySample> samples,
    required double width,
    required double height,
    bool showOverlay = true,
    bool showWatermark = true,
    Function(double)? onProgress,
    String? customDir,
  }) async {
    try {
      if (samples.isEmpty) return null;

      final String dirPath;
      if (customDir != null) {
        dirPath = customDir;
      } else {
        final tempDir = await getTemporaryDirectory();
        dirPath = p.join(tempDir.path, 'overlay_seq_${DateTime.now().millisecondsSinceEpoch}');
      }
      
      final sequenceDir = Directory(dirPath);
      if (!await sequenceDir.exists()) {
        await sequenceDir.create(recursive: true);
      }

      final svgString = await rootBundle.loadString(assetName);
      final PictureInfo pictureInfo = await svg.vg.loadPicture(
        svg.SvgStringLoader(svgString),
        null,
      );

      // 🔥 OPTIMIZATION: Parallel batch generation to maximize CPU/GPU utilization
      const int batchSize = 4;
      for (int i = 0; i < samples.length; i += batchSize) {
        final List<Future<void>> batchTasks = [];
        
        for (int j = 0; j < batchSize && (i + j) < samples.length; j++) {
          final int index = i + j;
          batchTasks.add(Future(() async {
            final sample = samples[index];
            final pngBytes = await generateSingleFrameBytes(
              data: sample.data,
              orientation: sample.orientation,
              width: width,
              height: height,
              showOverlay: showOverlay,
              showWatermark: showWatermark,
              settings: sample.settings,
              pictureInfo: pictureInfo,
            );

            if (pngBytes != null) {
              final file = File(p.join(
                sequenceDir.path,
                'frame_${index.toString().padLeft(5, '0')}.png',
              ));
              await file.writeAsBytes(pngBytes, flush: false);
            }
          }));
        }

        await Future.wait(batchTasks);

        // Report progress for image generation (0% to 40%)
        if (onProgress != null) {
          final currentProgress = min(1.0, (i + batchSize) / samples.length);
          onProgress(currentProgress);
        }

        if (i % 8 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      return sequenceDir.path;
    } catch (e) {
      debugPrint("Error generating sequence: $e");
      return null;
    }
  }

  static Future<Uint8List?> generateSingleFrameBytes({
    required OverlayData data,
    required DeviceOrientation orientation,
    required double width,
    required double height,
    required PictureInfo pictureInfo,
    bool showOverlay = true,
    bool showWatermark = true,
    OverlaySettings settings = const OverlaySettings(),
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    if (showOverlay) {
      final overlayPainter = LiveOverlayPainter(data, orientation, settings: settings);
      overlayPainter.paint(canvas, Size(width, height));
    }

    if (showWatermark) {
      canvas.save();
      _undoOrientationForVideoWatermark(canvas, orientation, width, height);

      final double baseSize = min(width, height);
      final double padding = baseSize * 0.04;

      final textPainter = TextPainter(
        text: TextSpan(
          text: "SurveyCam",
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

      final double svgSize = textPainter.height;
      const double spacing = 10;
      final double totalWidth = svgSize + spacing + textPainter.width;

      double dx, dy;
      if (orientation == DeviceOrientation.landscapeLeft || orientation == DeviceOrientation.landscapeRight) {
        dx = padding; dy = padding;
      } else {
        dx = width - totalWidth - padding; dy = padding;
      }

      canvas.save();
      canvas.translate(dx, dy);
      final double scale = svgSize / pictureInfo.size.height;
      canvas.scale(scale, scale);
      canvas.drawPicture(pictureInfo.picture);
      canvas.restore();

      textPainter.paint(canvas, Offset(dx + svgSize + spacing, dy));
      canvas.restore();
    }

    final picture = recorder.endRecording();
    final finalImage = await picture.toImage(width.toInt(), height.toInt());
    
    // 🔥 OPTIMIZATION: Use native PNG encoding instead of the pure-dart image package
    final byteData = await finalImage.toByteData(format: ui.ImageByteFormat.png);
    finalImage.dispose();

    return byteData?.buffer.asUint8List();
  }

  static Future<String?> applyOverlaySequenceToVideo({
    required String videoPath,
    required String sequenceDir,
    required int frameCount,
    required int durationMs,
    double sampleFps = overlaySampleFps,
    Function(double)? onProgress,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final outputPath = p.join(tempDir.path,
          'processed_video_${DateTime.now().millisecondsSinceEpoch}.mp4');

      // 🔥 HARDWARE ACCELERATION: Use mediacodec (Android) or videotoolbox (iOS) for near-instant encoding
      String encoder = 'libx264';
      String extraArgs =
          '-preset ultrafast -crf 23'; // Ultrafast for software fallback

      if (Platform.isAndroid) {
        encoder = 'h264_mediacodec';
        extraArgs = '-b:v 8M -profile:v high'; // High performance profile
      } else if (Platform.isIOS) {
        encoder = 'h264_videotoolbox';
        extraArgs = '-b:v 8M -profile:v high';
      }

      // FFmpeg command optimized for speed
      // [1:v]fps=$sampleFps ensures the overlay frames match the expected timing
      final command =
          '-i "$videoPath" -framerate $sampleFps -i "$sequenceDir/frame_%05d.png" '
          '-filter_complex "[0:v]scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(1080-iw)/2:(1920-ih)/2,setsar=1[v];'
          '[1:v]setpts=PTS-STARTPTS[ov];[v][ov]overlay=0:0" '
          '-c:v $encoder $extraArgs -codec:a copy -y "$outputPath"';

      debugPrint("Executing FFmpeg: $command");

      final Completer<String?> completer = Completer();

      await FFmpegKit.executeAsync(
        command,
        (session) async {
          final returnCode = await session.getReturnCode();
          debugPrint("FFmpeg finished with return code: $returnCode");

          // Cleanup sequence dir
          try {
            await Directory(sequenceDir).delete(recursive: true);
          } catch (_) {}

          if (ReturnCode.isSuccess(returnCode)) {
            if (onProgress != null) onProgress(1.0);
            completer.complete(outputPath);
          } else {
            final logs = await session.getAllLogsAsString();
            debugPrint("FFmpeg failed with hardware encoder. Logs: $logs");

            // FALLBACK to software encoding if hardware failed
            if (encoder != 'libx264') {
              debugPrint("Retrying with software encoder (libx264)...");
              final softwareCommand =
                  '-i "$videoPath" -framerate $sampleFps -i "$sequenceDir/frame_%05d.png" '
                  '-filter_complex "[0:v]scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(1080-iw)/2:(1920-ih)/2,setsar=1[v];'
                  '[1:v]setpts=PTS-STARTPTS[ov];[v][ov]overlay=0:0" '
                  '-c:v libx264 -preset ultrafast -crf 23 -codec:a copy -y "$outputPath"';

              final swSession = await FFmpegKit.execute(softwareCommand);
              final swReturnCode = await swSession.getReturnCode();

              if (ReturnCode.isSuccess(swReturnCode)) {
                completer.complete(outputPath);
              } else {
                completer.complete(null);
              }
            } else {
              completer.complete(null);
            }
          }
        },
        (log) => debugPrint(log.getMessage()),
        (statistics) {
          if (onProgress != null && durationMs > 0) {
            final time = statistics.getTime();
            if (time > 0) {
              final progress = (time / durationMs).clamp(0.0, 1.0);
              onProgress(progress);
            }
          }
        },
      );

      return completer.future;
    } catch (e) {
      debugPrint("Error applying sequence: $e");
      return null;
    }
  }

  static Future<Uint8List> generateVideoOverlayImage({
    required OverlayData data,
    required DeviceOrientation orientation,
    required double width,
    required double height,
    bool showOverlay = true,
    bool showWatermark = true,
    OverlaySettings settings = const OverlaySettings(),
  }) async {
    final svgString = await rootBundle.loadString(assetName);
    final PictureInfo pictureInfo = await svg.vg.loadPicture(
      svg.SvgStringLoader(svgString),
      null,
    );

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Video coordinates are typically fixed (e.g. 1080x1920)
    final double srcW = width;
    final double srcH = height;

    // Overlay
    if (showOverlay) {
      final overlayPainter = LiveOverlayPainter(data, orientation, settings: settings);
      overlayPainter.paint(
        canvas,
        Size(srcW, srcH),
      );
    }

    // ================= WATERMARK =================
    if (showWatermark) {
      canvas.save();

      _undoOrientationForVideoWatermark(
        canvas,
        orientation,
        srcW,
        srcH,
      );

      final double contentW = srcW;
      final double baseSize = min(srcW, srcH);
      final double padding = baseSize * 0.04;

      final textPainter = TextPainter(
        text: TextSpan(
          text: "SurveyCam",
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

      final double svgSize = textPainter.height;
      const double spacing = 10;
      final double totalWidth = svgSize + spacing + textPainter.width;

      double dx, dy;

      if (orientation == DeviceOrientation.landscapeLeft ||
          orientation == DeviceOrientation.landscapeRight) {
        // Landscape -> Top Left
        dx = padding;
        dy = padding;
      } else {
        // Portrait -> Top Right
        // Note: contentW and contentH are adjusted by _undoOrientation
        // For portraitUp, contentW is the short side.
        dx = contentW - totalWidth - padding;
        dy = padding;
      }

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

    final picture = recorder.endRecording();
    final finalImage = await picture.toImage(width.toInt(), height.toInt());

    final byteData =
        await finalImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    
    finalImage.dispose();

    if (byteData == null) return Uint8List(0);

    return await compute(_encodePngTask, {
      'width': finalImage.width,
      'height': finalImage.height,
      'buffer': byteData.buffer,
    });
  }

  static Uint8List _encodePngTask(Map<String, dynamic> params) {
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
      img.encodePng(processedImage),
    );
  }

  static Future<String?> applyOverlayToVideo({
    required String videoPath,
    required Uint8List overlayBytes,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final overlayFile = File(p.join(tempDir.path, 'video_overlay.png'));
      await overlayFile.writeAsBytes(overlayBytes);

      final outputPath = p.join(tempDir.path, 'processed_video_${DateTime.now().millisecondsSinceEpoch}.mp4');

      // Optimized FFmpeg command for speed with explicit scaling to 1080x1920
      const String filter = '[0:v]scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(1080-iw)/2:(1920-ih)/2,setsar=1[v];[v][1:v]overlay=0:0';
      final command = '-i "$videoPath" -i "${overlayFile.path}" -filter_complex "$filter" -c:v libx264 -preset ultrafast -crf 23 -codec:a copy -y "$outputPath"';

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        return outputPath;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  static Future<String?> mergeVideos(List<String> paths, {List<bool>? mirrorMap}) async {
    if (paths.isEmpty) return null;
    // If only one segment and NO mirroring needed, we can return as is
    if (paths.length == 1 && (mirrorMap == null || !mirrorMap[0])) return paths.first;

    try {
      final tempDir = await getTemporaryDirectory();
      final outputPath = p.join(tempDir.path, 'merged_video_${DateTime.now().millisecondsSinceEpoch}.mp4');

      String inputArgs = '';
      String filterComplex = '';
      for (int i = 0; i < paths.length; i++) {
        inputArgs += '-i "${paths[i]}" ';
        
        final bool isMirrored = (mirrorMap != null && i < mirrorMap.length) ? mirrorMap[i] : false;
        final String hflip = isMirrored ? 'hflip,' : '';

        filterComplex += '[$i:v]${hflip}scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(1080-iw)/2:(1920-ih)/2,setsar=1[v$i];';
      }

      for (int i = 0; i < paths.length; i++) {
        filterComplex += '[v$i][$i:a]';
      }
      filterComplex += 'concat=n=${paths.length}:v=1:a=1[outv][outa]';

      // Optimized FFmpeg command for merging speed
      final command = '$inputArgs -filter_complex "$filterComplex" -map "[outv]" -map "[outa]" -c:v libx264 -preset ultrafast -crf 23 -y "$outputPath"';

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        return outputPath;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }
}
