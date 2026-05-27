import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/core/services/video_processing_job.dart';
import 'package:surveycam/features/camera/domain/camera_lens_type.dart';
import 'package:surveycam/features/overlay/domain/WatermarkPosition.dart';
import 'package:surveycam/features/overlay/domain/overlay_model.dart';
import 'package:surveycam/features/overlay/domain/overlay_settings.dart';
import 'package:surveycam/features/overlay/domain/video_overlay_sample.dart';
import 'package:surveycam/features/overlay/presentation/video_watermark_processor.dart';

const _overlayData = OverlayData(
  dateTime: '',
  latitude: 0,
  longitude: 0,
  altitude: 0,
  heading: 0,
  direction: '',
  note: '',
);

VideoOverlaySample _sample(DeviceOrientation orientation, int timestampMs) {
  return VideoOverlaySample(
    data: _overlayData,
    orientation: orientation,
    settings: const OverlaySettings(),
    timestampMs: timestampMs,
  );
}

void main() {
  test('video processing keeps the recording start orientation', () {
    final samples = [
      _sample(DeviceOrientation.portraitUp, 0),
      _sample(DeviceOrientation.landscapeLeft, 500),
      _sample(DeviceOrientation.landscapeLeft, 1000),
      _sample(DeviceOrientation.landscapeRight, 1500),
    ];

    expect(
      VideoWatermarkProcessor.preferredOrientationForSamples(samples),
      DeviceOrientation.portraitUp,
    );
  });

  test('video processing returns null orientation without samples', () {
    expect(VideoWatermarkProcessor.preferredOrientationForSamples([]), isNull);
  });

  test('landscape-start overlay does not double rotate on landscape frame', () {
    expect(
      VideoWatermarkProcessor.shouldRotateVideoOverlayForFrame(
        frameSize: const Size(1920, 1080),
        orientation: DeviceOrientation.landscapeLeft,
      ),
      isFalse,
    );
  });

  test('portrait-start recording still rotates landscape overlay samples', () {
    expect(
      VideoWatermarkProcessor.shouldRotateVideoOverlayForFrame(
        frameSize: const Size(1080, 1920),
        orientation: DeviceOrientation.landscapeLeft,
      ),
      isTrue,
    );
  });

  test('saved video overlay paints in final frame coordinates', () {
    expect(
      VideoWatermarkProcessor.overlayPaintOrientationForFrame(
        frameSize: const Size(1080, 1920),
        orientation: DeviceOrientation.landscapeLeft,
      ),
      DeviceOrientation.landscapeLeft,
    );
    expect(
      VideoWatermarkProcessor.overlayPaintOrientationForFrame(
        frameSize: const Size(1920, 1080),
        orientation: DeviceOrientation.landscapeRight,
      ),
      DeviceOrientation.portraitUp,
    );
  });

  test('video overlay sample preserves position changes in the timeline', () {
    final samples = [
      VideoOverlaySample(
        data: _overlayData.copyWith(position: WatermarkPosition.bottomLeft),
        orientation: DeviceOrientation.portraitUp,
        settings: const OverlaySettings(),
        timestampMs: 0,
      ),
      VideoOverlaySample(
        data: _overlayData.copyWith(position: WatermarkPosition.bottomRight),
        orientation: DeviceOrientation.portraitUp,
        settings: const OverlaySettings(),
        timestampMs: 500,
      ),
    ];

    final roundTrip = samples
        .map((sample) => VideoOverlaySample.fromJson(sample.toJson()))
        .toList();

    expect(roundTrip.first.data.position, WatermarkPosition.bottomLeft);
    expect(roundTrip.last.data.position, WatermarkPosition.bottomRight);
    expect(roundTrip.last.timestampMs, 500);
  });

  test('overlay frames are capped to recording duration, not sample count', () {
    final samples = List.generate(
      120,
      (index) => VideoOverlaySample(
        data: _overlayData.copyWith(
          position: index < 4
              ? WatermarkPosition.bottomLeft
              : WatermarkPosition.bottomRight,
        ),
        orientation: DeviceOrientation.portraitUp,
        settings: const OverlaySettings(),
        timestampMs: index * 500,
      ),
    );

    final frames = VideoWatermarkProcessor.samplesForOverlayFrames(
      samples: samples,
      durationMs: 4000,
      sampleFps: 2,
    );

    expect(frames.length, 9);
    expect(frames.last.timestampMs, 4000);
    expect(frames.last.data.position, WatermarkPosition.bottomRight);
  });

  test('ffmpeg duration limit uses recording duration to prevent frozen tail',
      () {
    expect(
      VideoWatermarkProcessor.ffmpegDurationLimitArg(4123),
      '-t 4.123 ',
    );
    expect(VideoWatermarkProcessor.ffmpegDurationLimitArg(0), '');
  });

  test('fallback saves a processed merge before original segments', () {
    final paths = VideoProcessingFallback.rawSavePaths(
      mergedPath: 'merged.mp4',
      segments: const [
        VideoProcessingSegment(
          path: 'first.mp4',
          lens: CameraLensType.normal,
        ),
        VideoProcessingSegment(
          path: 'second.mp4',
          lens: CameraLensType.front,
          mirror: true,
        ),
      ],
    );

    expect(paths, ['merged.mp4']);
  });

  test('fallback saves one raw segment when no merge exists', () {
    final paths = VideoProcessingFallback.rawSavePaths(
      segments: const [
        VideoProcessingSegment(
          path: 'single.mp4',
          lens: CameraLensType.normal,
        ),
      ],
    );

    expect(paths, ['single.mp4']);
  });

  test('fallback saves all raw segments when merge cannot be produced', () {
    final paths = VideoProcessingFallback.rawSavePaths(
      segments: const [
        VideoProcessingSegment(
          path: 'first.mp4',
          lens: CameraLensType.normal,
        ),
        VideoProcessingSegment(
          path: 'second.mp4',
          lens: CameraLensType.front,
          mirror: true,
        ),
      ],
    );

    expect(paths, ['first.mp4', 'second.mp4']);
  });

  test('merge fit filter preserves full frame instead of cropping', () {
    final filter = VideoWatermarkProcessor.fitVideoInsideCanvasFilter(
      width: 1080,
      height: 1920,
    );

    expect(filter, contains('force_original_aspect_ratio=decrease'));
    expect(filter, contains('pad=1080:1920'));
    expect(filter, isNot(contains('crop=')));
  });

  test('merge fit filter mirrors without changing no-crop behavior', () {
    final filter = VideoWatermarkProcessor.fitVideoInsideCanvasFilter(
      width: 1080,
      height: 1920,
      mirror: true,
    );

    expect(filter, startsWith('hflip,'));
    expect(filter, contains('force_original_aspect_ratio=decrease'));
    expect(filter, isNot(contains('crop=')));
  });

  test('video normalization filter applies camera rotation metadata', () {
    expect(
      VideoWatermarkProcessor.normalizeVideoForOverlayFilter(0),
      '',
    );
    expect(
      VideoWatermarkProcessor.normalizeVideoForOverlayFilter(90),
      'transpose=clock,',
    );
    expect(
      VideoWatermarkProcessor.normalizeVideoForOverlayFilter(180),
      'transpose=clock,transpose=clock,',
    );
    expect(
      VideoWatermarkProcessor.normalizeVideoForOverlayFilter(270),
      'transpose=cclock,',
    );
    expect(
      VideoWatermarkProcessor.normalizeVideoForOverlayFilter(-90),
      'transpose=cclock,',
    );
  });

  test('front camera portrait correction is limited to portrait-up front lens',
      () {
    expect(
      VideoWatermarkProcessor.shouldApplyFrontCameraPortraitCorrection(
        lens: CameraLensType.front,
        recordingOrientation: DeviceOrientation.portraitUp,
      ),
      isTrue,
    );
    expect(
      VideoWatermarkProcessor.shouldApplyFrontCameraPortraitCorrection(
        lens: CameraLensType.normal,
        recordingOrientation: DeviceOrientation.portraitUp,
      ),
      isFalse,
    );
    expect(
      VideoWatermarkProcessor.shouldApplyFrontCameraPortraitCorrection(
        lens: CameraLensType.front,
        recordingOrientation: DeviceOrientation.landscapeLeft,
      ),
      isFalse,
    );
    expect(
      VideoWatermarkProcessor.shouldApplyFrontCameraPortraitCorrection(
        lens: CameraLensType.front,
        recordingOrientation: DeviceOrientation.portraitUp,
        mirrored: true,
      ),
      isFalse,
    );
  });

  test('front camera portrait correction adds a half turn after normalization',
      () {
    expect(
      VideoWatermarkProcessor.normalizeVideoForOverlayFilter(
        90,
        extraHalfTurn: true,
      ),
      'transpose=clock,transpose=clock,transpose=clock,',
    );
  });

  test('merge fit filter normalizes rotation before mirror and padding', () {
    final filter = VideoWatermarkProcessor.fitVideoInsideCanvasFilter(
      width: 1080,
      height: 1920,
      mirror: true,
      rotationDegrees: 90,
    );

    expect(filter, startsWith('transpose=clock,hflip,'));
    expect(filter, contains('pad=1080:1920'));
    expect(filter, isNot(contains('crop=')));
  });
}
