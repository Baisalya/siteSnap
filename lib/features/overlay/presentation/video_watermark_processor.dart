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
import 'package:surveycam/features/overlay/domain/overlay_render_snapshot.dart';
import 'package:surveycam/features/overlay/domain/overlay_settings.dart';
import 'package:surveycam/features/overlay/domain/WatermarkPosition.dart';
import 'package:surveycam/features/overlay/domain/video_overlay_sample.dart';
import 'package:surveycam/features/overlay/presentation/overlay_layout_engine.dart';

class VideoDimensions {
  final int width;
  final int height;

  const VideoDimensions({
    required this.width,
    required this.height,
  });
}

/// Strict stream identity used to decide whether MP4 segments can be joined
/// with `-c copy` without decoding/re-encoding frames.
class VideoStreamSignature {
  final String videoCodec;
  final String profile;
  final String pixelFormat;
  final String codecTag;
  final String videoTimeBase;
  final int width;
  final int height;
  final int level;
  final double frameRate;
  final int rotationDegrees;
  final bool hasAudio;
  final String audioCodec;
  final String audioProfile;
  final String audioTimeBase;
  final int sampleRate;
  final int channels;
  final String channelLayout;

  const VideoStreamSignature({
    required this.videoCodec,
    required this.profile,
    required this.pixelFormat,
    required this.codecTag,
    required this.videoTimeBase,
    required this.width,
    required this.height,
    required this.level,
    required this.frameRate,
    required this.rotationDegrees,
    required this.hasAudio,
    this.audioCodec = '',
    this.audioProfile = '',
    this.audioTimeBase = '',
    this.sampleRate = 0,
    this.channels = 0,
    this.channelLayout = '',
  });

  bool get isDefinitiveForStreamCopy {
    if (videoCodec.isEmpty ||
        pixelFormat.isEmpty ||
        videoTimeBase.isEmpty ||
        width <= 0 ||
        height <= 0 ||
        frameRate <= 0) {
      return false;
    }
    if (!hasAudio) return true;
    return audioCodec.isNotEmpty &&
        audioTimeBase.isNotEmpty &&
        sampleRate > 0 &&
        channels > 0;
  }

  bool isStreamCopyCompatibleWith(VideoStreamSignature other) {
    if (!isDefinitiveForStreamCopy || !other.isDefinitiveForStreamCopy) {
      return false;
    }
    if (videoCodec != other.videoCodec ||
        profile != other.profile ||
        pixelFormat != other.pixelFormat ||
        codecTag != other.codecTag ||
        videoTimeBase != other.videoTimeBase ||
        width != other.width ||
        height != other.height ||
        level != other.level ||
        rotationDegrees != other.rotationDegrees ||
        (frameRate - other.frameRate).abs() > 0.01 ||
        hasAudio != other.hasAudio) {
      return false;
    }

    if (!hasAudio) return true;
    return audioCodec == other.audioCodec &&
        audioProfile == other.audioProfile &&
        audioTimeBase == other.audioTimeBase &&
        sampleRate == other.sampleRate &&
        channels == other.channels &&
        channelLayout == other.channelLayout;
  }
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
  static PictureInfo? _realtimePictureInfo;
  static String? _realtimeCustomLogoPath;
  static ui.Image? _realtimeCustomLogo;

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
    return OverlayFrameGeometry.shouldRotateForFrame(
      frameSize: frameSize,
      orientation: orientation,
    );
  }

  static DeviceOrientation overlayPaintOrientationForFrame({
    required Size frameSize,
    required DeviceOrientation orientation,
  }) {
    return OverlayFrameGeometry.orientationForEncodedFrame(
      frameSize: frameSize,
      orientation: orientation,
    );
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

      return await _ffmpegKitChannel.invokeMethod<int>(
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

  static double _parseFrameRate(Object? value) {
    if (value is num) return value.toDouble();
    if (value is! String || value.isEmpty) return 0;
    final parts = value.split('/');
    if (parts.length == 2) {
      final numerator = double.tryParse(parts[0]);
      final denominator = double.tryParse(parts[1]);
      if (numerator != null && denominator != null && denominator != 0) {
        return numerator / denominator;
      }
    }
    return double.tryParse(value) ?? 0;
  }

  static int _parseInt(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static String _stringValue(Object? value) => value?.toString() ?? '';

  static Future<VideoStreamSignature?> getVideoStreamSignature(
    String videoPath,
  ) async {
    try {
      final mediaInfo = await _getNativeMediaInformation(videoPath);
      final streams = mediaInfo?['streams'] as List? ?? const [];
      Map<dynamic, dynamic>? video;
      Map<dynamic, dynamic>? audio;

      for (final rawStream in streams) {
        final stream = Map<dynamic, dynamic>.from(
          rawStream as Map? ?? const {},
        );
        if (stream['codec_type'] == 'video' && video == null) {
          video = stream;
        } else if (stream['codec_type'] == 'audio' && audio == null) {
          audio = stream;
        }
      }
      if (video == null) return null;

      final frameRate = _parseFrameRate(
        video['avg_frame_rate'] ?? video['r_frame_rate'],
      );
      final rotation =
          _normalizedRotationDegrees(_rotationDegreesForStream(video)).round() %
              360;

      return VideoStreamSignature(
        videoCodec: _stringValue(video['codec_name']),
        profile: _stringValue(video['profile']),
        pixelFormat: _stringValue(video['pix_fmt']),
        codecTag: _stringValue(video['codec_tag_string']),
        videoTimeBase: _stringValue(video['time_base']),
        width: _parseInt(video['width']),
        height: _parseInt(video['height']),
        level: _parseInt(video['level']),
        frameRate: frameRate,
        rotationDegrees: rotation,
        hasAudio: audio != null,
        audioCodec: _stringValue(audio?['codec_name']),
        audioProfile: _stringValue(audio?['profile']),
        audioTimeBase: _stringValue(audio?['time_base']),
        sampleRate: _parseInt(audio?['sample_rate']),
        channels: _parseInt(audio?['channels']),
        channelLayout: _stringValue(audio?['channel_layout']),
      );
    } catch (error) {
      debugPrint('Video stream signature probe failed: $error');
      return null;
    }
  }

  static Future<bool> canFastConcat(List<String> paths) async {
    if (paths.length < 2) return false;
    final signatures = await Future.wait(
      paths.map(getVideoStreamSignature),
    );
    if (signatures.any((signature) => signature == null)) return false;

    final first = signatures.first!;
    if (!first.isDefinitiveForStreamCopy) return false;
    return signatures
        .skip(1)
        .cast<VideoStreamSignature>()
        .every(first.isStreamCopyCompatibleWith);
  }

  static String _escapeFfconcatPath(String path) {
    // ffconcat uses single-quoted paths. Preserve Windows/Android backslashes
    // and escape embedded apostrophes using the concat-demuxer convention.
    return path.replaceAll('\\', '\\\\').replaceAll("'", r"'\''");
  }

  static Future<String?> _fastConcatVideos(
    List<String> paths,
    String outputPath,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final listFile = File(
      p.join(
        tempDir.path,
        'concat_${DateTime.now().microsecondsSinceEpoch}.txt',
      ),
    );

    try {
      final lines =
          paths.map((path) => "file '${_escapeFfconcatPath(path)}'").join('\n');
      await listFile.writeAsString('$lines\n', flush: true);

      final command = '-f concat -safe 0 -i "${listFile.path}" '
          '-map 0:v:0 -map 0:a? -c copy -movflags +faststart '
          '-avoid_negative_ts make_zero -y "$outputPath"';
      final returnCode = await _executeFfmpegCommand(command);
      if (returnCode == 0) {
        final outputFile = File(outputPath);
        if (await outputFile.exists() && await outputFile.length() > 0) {
          return outputPath;
        }
        debugPrint('Fast stream-copy concat produced an empty output file.');
        return null;
      }
      debugPrint('Fast stream-copy concat failed with code $returnCode.');
      return null;
    } finally {
      try {
        if (await listFile.exists()) await listFile.delete();
      } catch (_) {}
    }
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
      final customLogos = <String, ui.Image?>{};
      final logoPaths = frameSamples
          .map((sample) => sample.settings.activeWatermarkLogoPath)
          .whereType<String>()
          .where((path) => path.isNotEmpty)
          .toSet();
      try {
        for (final path in logoPaths) {
          customLogos[path] = await _loadCustomLogo(path);
        }

        const int batchSize = 4;
        for (int i = 0; i < frameSamples.length; i += batchSize) {
          if (await (shouldCancel?.call() ?? Future.value(false))) {
            try {
              await sequenceDir.delete(recursive: true);
            } catch (_) {}
            return null;
          }

          final List<Future<void>> batchTasks = [];

          for (int j = 0; j < batchSize && (i + j) < frameSamples.length; j++) {
            final int index = i + j;
            batchTasks.add(Future(() async {
              final sample = frameSamples[index];
              final customLogoPath = sample.settings.activeWatermarkLogoPath;
              final pngBytes = await generateSingleFrameBytes(
                data: sample.data,
                orientation: sample.orientation,
                width: width,
                height: height,
                showOverlay: showOverlay,
                showWatermark: showWatermark,
                settings: sample.settings,
                pictureInfo: pictureInfo,
                customLogo:
                    customLogoPath == null ? null : customLogos[customLogoPath],
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
      } catch (_) {
        try {
          await sequenceDir.delete(recursive: true);
        } catch (_) {}
        rethrow;
      } finally {
        for (final logo in customLogos.values) {
          logo?.dispose();
        }
        pictureInfo.picture.dispose();
      }
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
    required OverlaySettings settings,
    ui.Image? customLogo,
    bool useLandscapeLeftMarkedArea = false,
    bool displayOriented = false,
    WatermarkPosition? overlayPosition,
  }) {
    final double baseSize = min(size.width, size.height);
    const double margin = 15.0;
    final brandText = settings.activeWatermarkText.trim();
    final hasText = brandText.isNotEmpty;
    final hasLogo = settings.activeWatermarkShowLogo &&
        (settings.watermarkPresetIndex == 0 || customLogo != null);

    final textPainter = TextPainter(
      text: TextSpan(
        text: brandText,
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

    final double logoSize =
        hasLogo ? (hasText ? textPainter.height : baseSize * 0.06) : 0;
    final double spacing = hasLogo && hasText ? 10 : 0;
    final double boxWidth =
        logoSize + spacing + (hasText ? textPainter.width : 0);
    final double boxHeight = max(logoSize, hasText ? textPainter.height : 0);

    if (boxWidth <= 0 || boxHeight <= 0) return;

    // Realtime-video branding uses the same logical HUD coordinate system as
    // the information card: card at the selected bottom corner, branding at the
    // TOP of the same horizontal side. For a physical phone turn Flutter
    // re-authors this transparent HUD in fixed encoder coordinates; native GL
    // only alpha-blends it and never rotates/crops the camera texture.
    if (overlayPosition != null && displayOriented) {
      canvas.save();
      final targetX = overlayPosition == WatermarkPosition.bottomLeft
          ? margin
          : size.width - margin - boxWidth;
      final targetY = margin;
      canvas.translate(targetX, targetY);
      if (hasLogo) {
        _paintBrandLogo(
          canvas: canvas,
          offset: Offset.zero,
          size: logoSize,
          defaultLogo: pictureInfo,
          customLogo: customLogo,
        );
      }
      if (hasText) {
        textPainter.paint(canvas, Offset(logoSize + spacing, 0));
      }
      canvas.restore();
      return;
    }

    // Retain the previous transformed placement for non-display-oriented
    // callers. Current realtime video uses the branch above; legacy still/
    // FFmpeg paths remain untouched when [overlayPosition] is null.
    if (overlayPosition != null) {
      canvas.save();
      OverlayFrameGeometry.applyOrientationTransform(canvas, size, orientation);
      final logicalSize = OverlayFrameGeometry.logicalSizeForOrientation(
        size,
        orientation,
      );
      final targetX = overlayPosition == WatermarkPosition.bottomLeft
          ? logicalSize.width - margin - boxWidth
          : margin;
      final targetY = logicalSize.height - margin - boxHeight;
      canvas.translate(targetX, targetY);
      if (hasLogo) {
        _paintBrandLogo(
          canvas: canvas,
          offset: Offset.zero,
          size: logoSize,
          defaultLogo: pictureInfo,
          customLogo: customLogo,
        );
      }
      if (hasText) {
        textPainter.paint(canvas, Offset(logoSize + spacing, 0));
      }
      canvas.restore();
      return;
    }

    canvas.save();

    final bool isLandscape = displayOriented
        ? size.width > size.height
        : orientation == DeviceOrientation.landscapeLeft ||
            orientation == DeviceOrientation.landscapeRight;

    if (displayOriented) {
      final targetX = isLandscape ? margin : size.width - margin - boxWidth;
      final targetY = isLandscape ? size.height - margin - boxHeight : margin;
      canvas.translate(targetX, targetY);
      if (hasLogo) {
        _paintBrandLogo(
          canvas: canvas,
          offset: Offset.zero,
          size: logoSize,
          defaultLogo: pictureInfo,
          customLogo: customLogo,
        );
      }
      if (hasText) {
        textPainter.paint(canvas, Offset(logoSize + spacing, 0));
      }
      canvas.restore();
      return;
    }

    // Legacy encoded-frame placement keeps the original orientation contract.
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

    canvas.translate(targetX, targetY);

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

    if (hasLogo) {
      _paintBrandLogo(
        canvas: canvas,
        offset: Offset.zero,
        size: logoSize,
        defaultLogo: pictureInfo,
        customLogo: customLogo,
      );
    }

    if (hasText) {
      textPainter.paint(canvas, Offset(logoSize + spacing, 0));
    }

    canvas.restore();
  }

  static Future<ui.Image?> _loadCustomLogo(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
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

  static void _paintFrameContent({
    required Canvas canvas,
    required Size size,
    required OverlayData data,
    required DeviceOrientation orientation,
    required PictureInfo pictureInfo,
    ui.Image? customLogo,
    bool showOverlay = true,
    bool showWatermark = true,
    OverlaySettings settings = const OverlaySettings(),
    bool useLandscapeLeftMarkedArea = false,
    bool displayOriented = false,
    bool anchorWatermarkToOverlaySide = false,
  }) {
    if (showOverlay) {
      OverlayCardRenderer.paint(
        canvas: canvas,
        size: size,
        snapshot: OverlayRenderSnapshot(
          data: data,
          settings: settings,
          orientation:
              displayOriented ? DeviceOrientation.portraitUp : orientation,
        ),
      );
    }

    if (showWatermark) {
      _paintWatermark(
        canvas: canvas,
        size: size,
        orientation: orientation,
        pictureInfo: pictureInfo,
        settings: settings,
        customLogo: customLogo,
        useLandscapeLeftMarkedArea: useLandscapeLeftMarkedArea,
        displayOriented: displayOriented,
        overlayPosition: anchorWatermarkToOverlaySide ? data.position : null,
      );
    }
  }

  static Future<PictureInfo> _realtimeDefaultLogo() async {
    final cached = _realtimePictureInfo;
    if (cached != null) return cached;
    final svgString = await rootBundle.loadString(assetName);
    final loaded = await svg.vg.loadPicture(
      svg.SvgStringLoader(svgString),
      null,
    );
    _realtimePictureInfo = loaded;
    return loaded;
  }

  static Future<ui.Image?> _realtimeLogoForSettings(
    OverlaySettings settings,
  ) async {
    final path = settings.activeWatermarkLogoPath;
    if (path == _realtimeCustomLogoPath) return _realtimeCustomLogo;

    _realtimeCustomLogo?.dispose();
    _realtimeCustomLogo = null;
    _realtimeCustomLogoPath = path;
    if (path == null || path.isEmpty) return null;
    _realtimeCustomLogo = await _loadCustomLogo(path);
    return _realtimeCustomLogo;
  }

  /// Renders the app-owned overlay layer consumed by the recording-only
  /// CameraX VideoCapture compositor. Preview/ImageCapture do not use this
  /// method.
  ///
  /// [snapshot.orientation] is relative to the orientation at which the fixed
  /// encoder canvas was created (portraitUp means "same as recording start").
  /// The canvas itself never changes size during a clip. Instead, the logical
  /// overlay viewport is rotated inside that fixed canvas using the exact same
  /// orientation geometry as PHOTO/preview. Camera pixels are not transformed
  /// here or by the realtime overlay path.
  static Rect _centeredViewportForAspectRatio(
    Size frameSize,
    double? targetAspectRatio,
  ) {
    if (targetAspectRatio == null ||
        !targetAspectRatio.isFinite ||
        targetAspectRatio <= 0 ||
        frameSize.width <= 0 ||
        frameSize.height <= 0) {
      return Offset.zero & frameSize;
    }

    final frameAspect = frameSize.width / frameSize.height;
    if ((frameAspect - targetAspectRatio).abs() < 0.0001) {
      return Offset.zero & frameSize;
    }

    if (frameAspect > targetAspectRatio) {
      final viewportWidth = frameSize.height * targetAspectRatio;
      return Rect.fromLTWH(
        (frameSize.width - viewportWidth) / 2,
        0,
        viewportWidth,
        frameSize.height,
      );
    }

    final viewportHeight = frameSize.width / targetAspectRatio;
    return Rect.fromLTWH(
      0,
      (frameSize.height - viewportHeight) / 2,
      frameSize.width,
      viewportHeight,
    );
  }

  static Future<Uint8List?> generateRealtimeOverlayPng({
    required OverlayRenderSnapshot snapshot,
    required int width,
    required int height,
    double? viewportAspectRatio,
  }) async {
    if (width <= 0 || height <= 0) return null;

    final pictureInfo = await _realtimeDefaultLogo();
    final customLogo = await _realtimeLogoForSettings(snapshot.settings);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final frameSize = Size(width.toDouble(), height.toDouble());

    // Keep the encoded video canvas fixed while giving the overlay a logical
    // portrait/landscape canvas that follows the physical phone orientation.
    // This is equivalent to rotating a transparent HUD sheet over an untouched
    // camera recording: no camera zoom, crop, stretch, or letterbox is needed.
    canvas.save();
    OverlayFrameGeometry.applyOrientationTransform(
      canvas,
      frameSize,
      snapshot.orientation,
    );
    final logicalFrameSize = OverlayFrameGeometry.logicalSizeForOrientation(
      frameSize,
      snapshot.orientation,
    );
    final viewport = _centeredViewportForAspectRatio(
      logicalFrameSize,
      viewportAspectRatio,
    );
    canvas.translate(viewport.left, viewport.top);
    _paintFrameContent(
      canvas: canvas,
      size: viewport.size,
      data: snapshot.data,
      orientation: DeviceOrientation.portraitUp,
      pictureInfo: pictureInfo,
      customLogo: customLogo,
      settings: snapshot.settings,
      displayOriented: true,
      anchorWatermarkToOverlaySide: true,
    );
    canvas.restore();

    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(width, height);
      try {
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        return byteData?.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  static Future<Uint8List?> generateSingleFrameBytes({
    required OverlayData data,
    required DeviceOrientation orientation,
    required double width,
    required double height,
    required PictureInfo pictureInfo,
    ui.Image? customLogo,
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
      customLogo: customLogo,
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
      try {
        await Directory(sequenceDir).delete(recursive: true);
      } catch (_) {}
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

      final hasMirrorTransform = mirrorMap?.any((value) => value) ?? false;
      final hasPortraitCorrection =
          frontCameraPortraitCorrectionMap?.any((value) => value) ?? false;
      if (paths.length > 1 &&
          !hasMirrorTransform &&
          !hasPortraitCorrection &&
          await canFastConcat(paths)) {
        final fastPath = await _fastConcatVideos(paths, outputPath);
        if (fastPath != null) {
          debugPrint('Video segments finalized with stream-copy concat.');
          return fastPath;
        }
      }

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
