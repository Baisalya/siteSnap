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
import 'package:ffmpeg_kit_flutter_new_https_gpl/ffmpeg_kit_config.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'package:surveycam/features/overlay/domain/overlay_model.dart';
import 'package:surveycam/features/overlay/domain/overlay_settings.dart';
import 'package:surveycam/features/overlay/domain/video_overlay_sample.dart';
import 'package:surveycam/features/overlay/presentation/live_overlay_painter.dart';

class VideoDimensions {
  final int width;
  final int height;

  const VideoDimensions({
    required this.width,
    required this.height,
  });
}

class VideoWatermarkProcessor {
  static const String assetName = 'Assets/app_logo.svg';
  static const double overlaySampleFps = 2.0;
  static const double overlayWidth = 540;
  static const double overlayHeight = 960;
  static const MethodChannel _ffmpegKitChannel =
      MethodChannel('flutter.arthenica.com/ffmpeg_kit');
  static const VideoDimensions fallbackVideoDimensions = VideoDimensions(
    width: 1080,
    height: 1920,
  );

  static Future<int> _createNativeSession(
    String method,
    List<String> arguments,
  ) async {
    final session = await _ffmpegKitChannel.invokeMethod<Map<dynamic, dynamic>>(
      method,
      {'arguments': arguments},
    );
    final sessionId = (session?['sessionId'] as num?)?.toInt();
    if (sessionId == null) {
      throw StateError('Unable to create FFmpegKit session.');
    }
    return sessionId;
  }

  static Future<int?> _executeFfmpegCommand(String command) async {
    final sessionId = await _createNativeSession(
      'ffmpegSession',
      FFmpegKitConfig.parseArguments(command),
    );

    await _ffmpegKitChannel.invokeMethod<void>(
      'ffmpegSessionExecute',
      {'sessionId': sessionId},
    );

    return _ffmpegKitChannel.invokeMethod<int>(
      'abstractSessionGetReturnCode',
      {'sessionId': sessionId},
    );
  }

  static Future<Map<dynamic, dynamic>?> _getNativeMediaInformation(
    String videoPath,
  ) async {
    final sessionId = await _createNativeSession(
      'mediaInformationSession',
      [
        '-v',
        'error',
        '-hide_banner',
        '-print_format',
        'json',
        '-show_format',
        '-show_streams',
        '-show_chapters',
        '-i',
        videoPath,
      ],
    );

    await _ffmpegKitChannel.invokeMethod<void>(
      'mediaInformationSessionExecute',
      {
        'sessionId': sessionId,
        'waitTimeout': null,
      },
    );

    return _ffmpegKitChannel.invokeMethod<Map<dynamic, dynamic>>(
      'getMediaInformation',
      {'sessionId': sessionId},
    );
  }

  static double? _parseRotationValue(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static double _rotationDegreesForStream(Map<dynamic, dynamic> streamMap) {
    final tags = streamMap['tags'];
    if (tags is Map) {
      final rotation = _parseRotationValue(tags['rotate']);
      if (rotation != null) return rotation;
    }

    final sideDataList = streamMap['side_data_list'];
    if (sideDataList is List) {
      for (final sideData in sideDataList) {
        if (sideData is! Map) continue;
        final rotation = _parseRotationValue(sideData['rotation']);
        if (rotation != null) return rotation;
      }
    }

    return 0;
  }

  static bool _isQuarterTurn(double rotationDegrees) {
    final turns = (rotationDegrees / 90).round().abs();
    return turns.isOdd;
  }

  static Future<VideoDimensions> getVideoDimensions(String videoPath) async {
    try {
      final mediaInfo = await _getNativeMediaInformation(videoPath);
      final streams = mediaInfo?['streams'] as List? ?? const [];

      for (final stream in streams) {
        final streamMap = Map<dynamic, dynamic>.from(
          stream as Map? ?? const {},
        );
        if (streamMap['codec_type'] != 'video') continue;

        final width = (streamMap['width'] as num?)?.toInt();
        final height = (streamMap['height'] as num?)?.toInt();
        if (width != null && height != null && width > 0 && height > 0) {
          final rotationDegrees = _rotationDegreesForStream(streamMap);
          if (_isQuarterTurn(rotationDegrees)) {
            return VideoDimensions(
              width: height,
              height: width,
            );
          }

          return VideoDimensions(
            width: width,
            height: height,
          );
        }
      }
    } catch (e) {
      debugPrint("Video dimension probe failed: $e");
    }

    return fallbackVideoDimensions;
  }

  static ({String encoder, String args}) _encoderSettings() {
    if (Platform.isAndroid) {
      return (encoder: 'h264_mediacodec', args: '-b:v 8M -profile:v high');
    }
    if (Platform.isIOS) {
      return (encoder: 'h264_videotoolbox', args: '-b:v 8M -profile:v high');
    }
    return (encoder: 'libx264', args: '-preset ultrafast -crf 23');
  }

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
        dirPath = p.join(tempDir.path,
            'overlay_seq_${DateTime.now().millisecondsSinceEpoch}');
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
      final overlayPainter =
          LiveOverlayPainter(data, orientation, settings: settings);
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
      if (orientation == DeviceOrientation.landscapeLeft ||
          orientation == DeviceOrientation.landscapeRight) {
        dx = padding;
        dy = padding;
      } else {
        dx = width - totalWidth - padding;
        dy = padding;
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
    final byteData =
        await finalImage.toByteData(format: ui.ImageByteFormat.png);
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
      final encoderSettings = _encoderSettings();
      final encoder = encoderSettings.encoder;
      final extraArgs = encoderSettings.args;

      // FFmpeg command optimized for speed
      // [1:v]fps=$sampleFps ensures the overlay frames match the expected timing
      const filter = '[0:v]setsar=1[base];[1:v]setpts=PTS-STARTPTS[ov];'
          '[base][ov]overlay=0:0:format=auto,format=yuv420p[v]';
      final command =
          '-i "$videoPath" -framerate $sampleFps -i "$sequenceDir/frame_%05d.png" '
          '-filter_complex "$filter" -map "[v]" -map 0:a? '
          '-c:v $encoder $extraArgs -pix_fmt yuv420p -c:a copy '
          '-movflags +faststart -y "$outputPath"';

      debugPrint("Executing FFmpeg: $command");

      String? completedPath;

      onProgress?.call(0.05);
      final returnCode = await _executeFfmpegCommand(command);
      debugPrint("FFmpeg finished with return code: $returnCode");

      if (returnCode == 0) {
        onProgress?.call(1.0);
        completedPath = outputPath;
      } else {
        debugPrint("FFmpeg failed with hardware encoder: $returnCode");

        if (encoder != 'libx264') {
          debugPrint("Retrying with software encoder (libx264)...");
          final softwareCommand =
              '-i "$videoPath" -framerate $sampleFps -i "$sequenceDir/frame_%05d.png" '
              '-filter_complex "$filter" -map "[v]" -map 0:a? '
              '-c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p '
              '-c:a copy -movflags +faststart -y "$outputPath"';

          final swReturnCode = await _executeFfmpegCommand(softwareCommand);

          if (swReturnCode == 0) {
            onProgress?.call(1.0);
            completedPath = outputPath;
          }
        }
      }

      try {
        await Directory(sequenceDir).delete(recursive: true);
      } catch (_) {}

      return completedPath;
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
      final overlayPainter =
          LiveOverlayPainter(data, orientation, settings: settings);
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

      final outputPath = p.join(tempDir.path,
          'processed_video_${DateTime.now().millisecondsSinceEpoch}.mp4');

      // Optimized FFmpeg command for speed with explicit scaling to 1080x1920
      const String filter =
          '[0:v]scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(1080-iw)/2:(1920-ih)/2,setsar=1[v];[v][1:v]overlay=0:0';
      final command =
          '-i "$videoPath" -i "${overlayFile.path}" -filter_complex "$filter" -c:v libx264 -preset ultrafast -crf 23 -codec:a copy -y "$outputPath"';

      final returnCode = await _executeFfmpegCommand(command);

      if (returnCode == 0) {
        return outputPath;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  static Future<String?> mergeVideos(
    List<String> paths, {
    List<bool>? mirrorMap,
  }) async {
    if (paths.isEmpty) return null;

    final firstMirror =
        mirrorMap != null && mirrorMap.isNotEmpty ? mirrorMap.first : false;
    if (paths.length == 1 && !firstMirror) return paths.first;

    try {
      final tempDir = await getTemporaryDirectory();
      final outputPath = p.join(
        tempDir.path,
        'merged_video_${DateTime.now().millisecondsSinceEpoch}.mp4',
      );

      if (paths.length == 1) {
        final encoderSettings = _encoderSettings();
        final command =
            '-i "${paths.first}" -vf "hflip,format=yuv420p" -map 0:a? '
            '-c:v ${encoderSettings.encoder} ${encoderSettings.args} '
            '-pix_fmt yuv420p -c:a copy -movflags +faststart -y "$outputPath"';

        final returnCode = await _executeFfmpegCommand(command);
        return returnCode == 0 ? outputPath : null;
      }

      final targetSize = await getVideoDimensions(paths.first);

      String inputArgs = '';
      String filterComplex = '';
      for (int i = 0; i < paths.length; i++) {
        inputArgs += '-i "${paths[i]}" ';

        final bool isMirrored =
            (mirrorMap != null && i < mirrorMap.length) ? mirrorMap[i] : false;
        final String hflip = isMirrored ? 'hflip,' : '';

        filterComplex +=
            '[$i:v]${hflip}scale=${targetSize.width}:${targetSize.height}:force_original_aspect_ratio=increase,'
            'crop=${targetSize.width}:${targetSize.height}:(iw-${targetSize.width})/2:(ih-${targetSize.height})/2,'
            'setsar=1,format=yuv420p[v$i];';
      }

      for (int i = 0; i < paths.length; i++) {
        filterComplex += '[v$i][$i:a]';
      }
      filterComplex += 'concat=n=${paths.length}:v=1:a=1[outv][outa]';

      final command =
          '$inputArgs -filter_complex "$filterComplex" -map "[outv]" -map "[outa]" '
          '-c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p '
          '-c:a aac -b:a 128k -movflags +faststart -y "$outputPath"';

      final returnCode = await _executeFfmpegCommand(command);

      if (returnCode == 0) {
        return outputPath;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }
}
