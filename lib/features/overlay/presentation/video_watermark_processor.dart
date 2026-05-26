import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart' as svg;
import 'package:ffmpeg_kit_flutter_new_https_gpl/ffmpeg_kit.dart';
import 'package:vector_graphics/vector_graphics.dart';
import 'package:ffmpeg_kit_flutter_new_https_gpl/ffmpeg_kit_config.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'package:surveycam/features/camera/domain/camera_lens_type.dart';
import 'package:surveycam/features/overlay/domain/overlay_model.dart';
import 'package:surveycam/features/overlay/domain/overlay_settings.dart';
import 'package:surveycam/features/overlay/domain/video_overlay_sample.dart';

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
  static final Set<int> _activeFfmpegSessionIds = <int>{};
  static const VideoDimensions fallbackVideoDimensions = VideoDimensions(
    width: 1080,
    height: 1920,
  );

  static DeviceOrientation? preferredOrientationForSamples(
    List<VideoOverlaySample> samples,
  ) {
    if (samples.isEmpty) return null;
    return samples.first.orientation;
  }

  static bool shouldRotateVideoOverlayForFrame({
    required Size frameSize,
    required DeviceOrientation orientation,
  }) {
    final frameIsLandscape = frameSize.width > frameSize.height;
    final overlayIsLandscape = orientation == DeviceOrientation.landscapeLeft ||
        orientation == DeviceOrientation.landscapeRight;
    return frameIsLandscape != overlayIsLandscape;
  }

  static DeviceOrientation overlayPaintOrientationForFrame({
    required Size frameSize,
    required DeviceOrientation orientation,
  }) {
    final isFrameLandscape = frameSize.width > frameSize.height;

    if (isFrameLandscape) {
      // If the video frame itself is landscape (e.g. 1920x1080),
      // we need to translate the device's sensor orientation into a logical
      // orientation relative to that landscape canvas.
      switch (orientation) {
        case DeviceOrientation.landscapeLeft:
          return DeviceOrientation.portraitUp;
        case DeviceOrientation.landscapeRight:
          return DeviceOrientation.portraitUp;
        case DeviceOrientation.portraitUp:
          return DeviceOrientation.landscapeLeft;
        case DeviceOrientation.portraitDown:
          return DeviceOrientation.landscapeRight;
      }
    }

    return orientation;
  }

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
    _activeFfmpegSessionIds.add(sessionId);

    try {
      await _ffmpegKitChannel.invokeMethod<void>(
        'ffmpegSessionExecute',
        {'sessionId': sessionId},
      );

      return _ffmpegKitChannel.invokeMethod<int>(
        'abstractSessionGetReturnCode',
        {'sessionId': sessionId},
      );
    } finally {
      _activeFfmpegSessionIds.remove(sessionId);
    }
  }

  static Future<void> cancelActiveProcessing() async {
    if (_activeFfmpegSessionIds.isEmpty) {
      await FFmpegKit.cancel();
      return;
    }

    await Future.wait(
      _activeFfmpegSessionIds.map((sessionId) => FFmpegKit.cancel(sessionId)),
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
    if (value is num) {
      // Handle TIFF/EXIF orientation integers
      if (value == 3) return 180;
      if (value == 6) return 90;
      if (value == 8) return 270;
      return value.toDouble();
    }
    if (value is String) {
      final doubleValue = double.tryParse(value);
      if (doubleValue != null) return _parseRotationValue(doubleValue);
    }
    return null;
  }

  static double _rotationDegreesForStream(Map<dynamic, dynamic> streamMap) {
    final tags = streamMap['tags'];
    if (tags is Map) {
      final rotation = _parseRotationValue(tags['rotate']) ??
          _parseRotationValue(tags['orientation']);
      if (rotation != null) return rotation;
    }

    final sideDataList = streamMap['side_data_list'];
    if (sideDataList is List) {
      for (final sideData in sideDataList) {
        if (sideData is! Map) continue;

        var rotation = _parseRotationValue(sideData['rotation']);
        if (rotation != null) return rotation;

        if (sideData['side_data_type'] == 'Display Matrix') {
          rotation = _parseRotationValue(sideData['rotation']);
          if (rotation != null) return rotation;
        }
      }
    }

    return 0;
  }

  static bool _isQuarterTurn(double rotationDegrees) {
    final turns = (rotationDegrees / 90).round().abs();
    return turns.isOdd;
  }

  static double _normalizedRotationDegrees(double rotationDegrees) {
    final normalized = rotationDegrees % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }

  static bool shouldApplyFrontCameraPortraitCorrection({
    required CameraLensType lens,
    required DeviceOrientation? recordingOrientation,
    bool mirrored = false,
  }) {
    return !mirrored &&
        lens == CameraLensType.front &&
        recordingOrientation == DeviceOrientation.portraitUp;
  }

  static String normalizeVideoForOverlayFilter(
    double rotationDegrees, {
    bool extraHalfTurn = false,
  }) {
    final String normalizeFilter;
    switch (_normalizedRotationDegrees(rotationDegrees).round()) {
      case 90:
        normalizeFilter = 'transpose=clock,';
        break;
      case 180:
        normalizeFilter = 'transpose=clock,transpose=clock,';
        break;
      case 270:
        normalizeFilter = 'transpose=cclock,';
        break;
      default:
        normalizeFilter = '';
    }

    final halfTurnFilter =
        extraHalfTurn ? 'transpose=clock,transpose=clock,' : '';
    return '$normalizeFilter$halfTurnFilter';
  }

  static Future<double> getVideoRotationDegrees(String videoPath) async {
    try {
      final mediaInfo = await _getNativeMediaInformation(videoPath);
      final streams = mediaInfo?['streams'] as List? ?? const [];

      for (final stream in streams) {
        final streamMap = Map<dynamic, dynamic>.from(
          stream as Map? ?? const {},
        );
        if (streamMap['codec_type'] != 'video') continue;
        final streamRotation = _rotationDegreesForStream(streamMap);
        if (streamRotation != 0) return streamRotation;
      }

      // Fallback to global format tags (sometimes rotate is there)
      final format = mediaInfo?['format'];
      if (format is Map) {
        final tags = format['tags'];
        if (tags is Map) {
          final rotation = _parseRotationValue(tags['rotate']) ??
              _parseRotationValue(tags['orientation']);
          if (rotation != null) return rotation;
        }
      }
    } catch (e) {
      debugPrint("Video rotation probe failed: $e");
    }

    return 0;
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

  static double? _parseDurationSeconds(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static Future<int?> getVideoDurationMs(String videoPath) async {
    try {
      final mediaInfo = await _getNativeMediaInformation(videoPath);
      final format = mediaInfo?['format'];
      final duration = _parseDurationSeconds(mediaInfo?['duration']) ??
          _parseDurationSeconds(format is Map ? format['duration'] : null);
      if (duration != null && duration > 0) {
        return (duration * 1000).round();
      }

      final streams = mediaInfo?['streams'] as List? ?? const [];
      for (final stream in streams) {
        final streamMap = Map<dynamic, dynamic>.from(
          stream as Map? ?? const {},
        );
        if (streamMap['codec_type'] != 'video') continue;
        final streamDuration = _parseDurationSeconds(streamMap['duration']);
        if (streamDuration != null && streamDuration > 0) {
          return (streamDuration * 1000).round();
        }
      }
    } catch (e) {
      debugPrint("Video duration probe failed: $e");
    }

    return null;
  }

  static List<VideoOverlaySample> samplesForOverlayFrames({
    required List<VideoOverlaySample> samples,
    required int durationMs,
    double sampleFps = overlaySampleFps,
  }) {
    if (samples.isEmpty) return const [];
    if (durationMs <= 0 || sampleFps <= 0) {
      return List<VideoOverlaySample>.from(samples);
    }

    final sorted = List<VideoOverlaySample>.from(samples)
      ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    final frameCount = max(1, (durationMs / 1000 * sampleFps).ceil() + 1);
    final frames = <VideoOverlaySample>[];
    var sampleIndex = 0;

    for (var frameIndex = 0; frameIndex < frameCount; frameIndex++) {
      final targetMs = min(
        durationMs,
        (frameIndex * 1000 / sampleFps).round(),
      );
      while (sampleIndex + 1 < sorted.length &&
          sorted[sampleIndex + 1].timestampMs <= targetMs) {
        sampleIndex++;
      }
      final sample = sorted[sampleIndex];
      frames.add(VideoOverlaySample(
        data: sample.data,
        orientation: sample.orientation,
        settings: sample.settings,
        timestampMs: targetMs,
      ));
    }

    return frames;
  }

  static String ffmpegDurationLimitArg(int durationMs) {
    if (durationMs <= 0) return '';
    final seconds = (durationMs / 1000).toStringAsFixed(3);
    return '-t $seconds ';
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

  static String fitVideoInsideCanvasFilter({
    required int width,
    required int height,
    bool mirror = false,
    double rotationDegrees = 0,
    bool extraHalfTurn = false,
  }) {
    final normalizeFilter = normalizeVideoForOverlayFilter(
      rotationDegrees,
      extraHalfTurn: extraHalfTurn,
    );
    final hflip = mirror ? 'hflip,' : '';
    return '$normalizeFilter${hflip}scale=$width:$height:force_original_aspect_ratio=decrease,'
        'pad=$width:$height:(ow-iw)/2:(oh-ih)/2,'
        'setsar=1,format=yuv420p';
  }

  static Future<String?> generateVideoOverlaySequence({
    required List<VideoOverlaySample> samples,
    required double width,
    required double height,
    int durationMs = 0,
    double sampleFps = overlaySampleFps,
    bool showOverlay = true,
    bool showWatermark = true,
    Function(double)? onProgress,
    FutureOr<bool> Function()? shouldCancel,
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
      final frameSamples = samplesForOverlayFrames(
        samples: samples,
        durationMs: durationMs,
        sampleFps: sampleFps,
      );

      const int batchSize = 4;
      for (int i = 0; i < frameSamples.length; i += batchSize) {
        if (await (shouldCancel?.call() ?? Future.value(false))) {
          return null;
        }

        final List<Future<void>> batchTasks = [];

        for (int j = 0; j < batchSize && (i + j) < frameSamples.length; j++) {
          final int index = i + j;
          batchTasks.add(Future(() async {
            final sample = frameSamples[index];
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
          final currentProgress =
              min(1.0, (i + batchSize) / frameSamples.length);
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

  static void _paintWatermark({
    required Canvas canvas,
    required Size size,
    required DeviceOrientation orientation,
    required PictureInfo pictureInfo,
    bool useLandscapeLeftMarkedArea = false,
  }) {
    final double baseSize = min(size.width, size.height);
    const double margin = 15.0;

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
    final double boxWidth = svgSize + spacing + textPainter.width;
    final double boxHeight = svgSize;

    canvas.save();

    final bool isLandscape = orientation == DeviceOrientation.landscapeLeft ||
        orientation == DeviceOrientation.landscapeRight;

    // Swap positions in landscape: Watermark moves to Bottom-Left
    final double targetX;
    final double targetY;
    if (useLandscapeLeftMarkedArea) {
      targetX = margin + boxWidth;
      targetY = margin + boxHeight;
    } else if (isLandscape) {
      targetX = margin;
      targetY = size.height - margin;
    } else {
      targetX = size.width - margin;
      targetY = margin;
    }

    canvas.save();
    // Translate to the target corner
    canvas.translate(targetX, targetY);

    // Rotate content based on orientation
    switch (orientation) {
      case DeviceOrientation.portraitDown:
        canvas.rotate(pi);
        // After 180 deg rotation, we need to translate back to keep the box
        // within the intended area (upright relative to the rotation).
        canvas.translate(0, -boxHeight);
        break;
      case DeviceOrientation.landscapeLeft:
        canvas.rotate(-pi / 2);
        break;
      case DeviceOrientation.landscapeRight:
        canvas.rotate(pi / 2);
        // After 90 deg rotation, we need to translate to keep the box visible
        canvas.translate(-boxWidth, -boxHeight);
        break;
      default:
        if (useLandscapeLeftMarkedArea) {
          canvas.rotate(pi);
          break;
        }
        // portraitUp
        canvas.translate(-boxWidth, 0);
        break;
    }

    // Draw SVG
    canvas.save();
    final double scale = svgSize / pictureInfo.size.height;
    canvas.scale(scale, scale);
    canvas.drawPicture(pictureInfo.picture);
    canvas.restore();

    // Draw Text
    textPainter.paint(canvas, Offset(svgSize + spacing, 0));

    canvas.restore();
  }

  static void _paintFrameContent({
    required Canvas canvas,
    required Size size,
    required OverlayData data,
    required DeviceOrientation orientation,
    required PictureInfo pictureInfo,
    bool showOverlay = true,
    bool showWatermark = true,
    OverlaySettings settings = const OverlaySettings(),
    bool useLandscapeLeftMarkedArea = false,
  }) {
    if (showOverlay) {
      canvas.save();

      final double baseSize = min(size.width, size.height);
      final List<TextSpan> spans = [];
      final textStyle = TextStyle(
        color: settings.textColor,
        fontSize: baseSize * 0.032,
        fontWeight: FontWeight.w600,
      );
      final noteStyle = textStyle.copyWith(fontStyle: FontStyle.italic);
      final noteLines = settings.showNote && data.note.trim().isNotEmpty
          ? data.note.trim().split(RegExp(r'\r?\n'))
          : const <String>[];
      final placeLine = noteLines.isEmpty ? '' : noteLines.first.trim();
      final extraNote =
          noteLines.length <= 1 ? '' : noteLines.skip(1).join('\n').trim();

      if (placeLine.isNotEmpty) {
        spans.add(TextSpan(text: "$placeLine\n", style: noteStyle));
      }
      if (settings.showDateTime && data.dateTime.isNotEmpty) {
        spans.add(TextSpan(text: "${data.dateTime}\n", style: textStyle));
      }
      if (data.locationWarning != null) {
        spans.add(TextSpan(
            text: "${data.locationWarning}\n",
            style: textStyle.copyWith(color: Colors.redAccent)));
      } else if (settings.showCoordinates) {
        spans.add(TextSpan(
            text:
                "Lat: ${data.latitude.toStringAsFixed(6)}\nLon: ${data.longitude.toStringAsFixed(6)}\n",
            style: textStyle));
      }
      if (extraNote.isNotEmpty) {
        spans.add(TextSpan(text: extraNote, style: noteStyle));
      }
      final textPainter = TextPainter(
        text: TextSpan(children: spans),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: baseSize * 0.75);

      final paddingH = baseSize * 0.03;
      final paddingV = baseSize * 0.02;
      final boxWidth = textPainter.width + (paddingH * 2);
      final boxHeight = textPainter.height + (paddingV * 2);
      const double margin = 15.0;

      final bool isLandscape = orientation == DeviceOrientation.landscapeLeft ||
          orientation == DeviceOrientation.landscapeRight;

      // Swap positions in landscape: Overlay moves to Top-Right
      final double targetX;
      final double targetY;
      if (useLandscapeLeftMarkedArea) {
        targetX = size.width - margin;
        targetY = margin + boxHeight;
      } else if (isLandscape) {
        targetX = size.width - margin;
        targetY = margin;
      } else {
        targetX = margin;
        targetY = size.height - margin;
      }

      canvas.translate(targetX, targetY);

      switch (orientation) {
        case DeviceOrientation.portraitDown:
          canvas.rotate(pi);
          canvas.translate(-boxWidth, 0);
          break;
        case DeviceOrientation.landscapeLeft:
          canvas.rotate(-pi / 2);
          canvas.translate(-boxWidth, -boxHeight);
          break;
        case DeviceOrientation.landscapeRight:
          canvas.rotate(pi / 2);
          break;
        default:
          if (useLandscapeLeftMarkedArea) {
            canvas.rotate(pi);
            break;
          }
          // portraitUp
          canvas.translate(0, -boxHeight);
          break;
      }

      // Draw Background
      final rect = Rect.fromLTWH(0, 0, boxWidth, boxHeight);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        Paint()
          ..color = settings.backgroundColor
              .withValues(alpha: settings.backgroundOpacity),
      );

      // Draw Text
      textPainter.paint(canvas, Offset(paddingH, paddingV));

      canvas.restore();
    }

    if (showWatermark) {
      _paintWatermark(
        canvas: canvas,
        size: size,
        orientation: orientation,
        pictureInfo: pictureInfo,
        useLandscapeLeftMarkedArea: useLandscapeLeftMarkedArea,
      );
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
    final frameSize = Size(width, height);
    final paintOrientation = overlayPaintOrientationForFrame(
      frameSize: frameSize,
      orientation: orientation,
    );
    final useLandscapeLeftMarkedArea = frameSize.width > frameSize.height &&
        orientation == DeviceOrientation.landscapeLeft;

    _paintFrameContent(
      canvas: canvas,
      size: frameSize,
      data: data,
      orientation: paintOrientation,
      pictureInfo: pictureInfo,
      showOverlay: showOverlay,
      showWatermark: showWatermark,
      settings: settings,
      useLandscapeLeftMarkedArea: useLandscapeLeftMarkedArea,
    );

    final picture = recorder.endRecording();
    final finalImage = await picture.toImage(width.toInt(), height.toInt());

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
    bool correctFrontCameraPortrait = false,
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
      final rotationDegrees = await getVideoRotationDegrees(videoPath);
      final normalizeFilter = normalizeVideoForOverlayFilter(
        rotationDegrees,
        extraHalfTurn: correctFrontCameraPortrait,
      );
      final probedDurationMs = await getVideoDurationMs(videoPath);
      final outputDurationMs = probedDurationMs ?? durationMs;
      final durationLimitArg = ffmpegDurationLimitArg(outputDurationMs);
      final filter = '[0:v]${normalizeFilter}setsar=1[base];'
          '[1:v]setpts=PTS-STARTPTS[ov];'
          '[base][ov]overlay=0:0:format=auto:eof_action=pass:repeatlast=0,format=yuv420p[v]';
      final command =
          '-noautorotate -i "$videoPath" -framerate $sampleFps -i "$sequenceDir/frame_%05d.png" '
          '-filter_complex "$filter" -map "[v]" -map 0:a? '
          '-c:v $encoder $extraArgs -pix_fmt yuv420p -c:a copy '
          '-metadata:s:v:0 rotate=0 -movflags +faststart $durationLimitArg-y "$outputPath"';

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
              '-noautorotate -i "$videoPath" -framerate $sampleFps -i "$sequenceDir/frame_%05d.png" '
              '-filter_complex "$filter" -map "[v]" -map 0:a? '
              '-c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p '
              '-c:a copy -metadata:s:v:0 rotate=0 -movflags +faststart $durationLimitArg-y "$outputPath"';

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
    final frameSize = Size(width, height);

    _paintFrameContent(
      canvas: canvas,
      size: frameSize,
      data: data,
      orientation: orientation,
      pictureInfo: pictureInfo,
      showOverlay: showOverlay,
      showWatermark: showWatermark,
      settings: settings,
    );

    final picture = recorder.endRecording();
    final finalImage = await picture.toImage(width.toInt(), height.toInt());

    final byteData =
        await finalImage.toByteData(format: ui.ImageByteFormat.png);

    finalImage.dispose();

    return byteData?.buffer.asUint8List() ?? Uint8List(0);
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
    List<bool>? frontCameraPortraitCorrectionMap,
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
        final rotationDegrees = await getVideoRotationDegrees(paths.first);
        final extraHalfTurn = frontCameraPortraitCorrectionMap != null &&
            frontCameraPortraitCorrectionMap.isNotEmpty &&
            frontCameraPortraitCorrectionMap.first;
        final normalizeFilter = normalizeVideoForOverlayFilter(
          rotationDegrees,
          extraHalfTurn: extraHalfTurn,
        );
        final command =
            '-noautorotate -i "${paths.first}" -vf "${normalizeFilter}hflip,format=yuv420p" '
            '-map 0:v:0 -map 0:a? '
            '-c:v ${encoderSettings.encoder} ${encoderSettings.args} '
            '-pix_fmt yuv420p -c:a copy -metadata:s:v:0 rotate=0 '
            '-movflags +faststart -y "$outputPath"';

        final returnCode = await _executeFfmpegCommand(command);
        return returnCode == 0 ? outputPath : null;
      }

      final targetSize = await getVideoDimensions(paths.first);
      final rotationMap = await Future.wait(
        paths.map(getVideoRotationDegrees),
      );

      String inputArgs = '';
      String filterComplex = '';
      for (int i = 0; i < paths.length; i++) {
        inputArgs += '-noautorotate -i "${paths[i]}" ';

        final bool isMirrored =
            (mirrorMap != null && i < mirrorMap.length) ? mirrorMap[i] : false;

        final fitFilter = fitVideoInsideCanvasFilter(
          width: targetSize.width,
          height: targetSize.height,
          mirror: isMirrored,
          rotationDegrees: rotationMap[i],
          extraHalfTurn: frontCameraPortraitCorrectionMap != null &&
              i < frontCameraPortraitCorrectionMap.length &&
              frontCameraPortraitCorrectionMap[i],
        );

        filterComplex += '[$i:v]$fitFilter[v$i];';
      }

      for (int i = 0; i < paths.length; i++) {
        filterComplex += '[v$i][$i:a]';
      }
      filterComplex += 'concat=n=${paths.length}:v=1:a=1[outv][outa]';

      final command =
          '$inputArgs -filter_complex "$filterComplex" -map "[outv]" -map "[outa]" '
          '-c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p '
          '-c:a aac -b:a 128k -metadata:s:v:0 rotate=0 '
          '-movflags +faststart -y "$outputPath"';

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
