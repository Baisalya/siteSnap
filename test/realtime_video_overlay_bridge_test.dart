import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/features/camera/data/realtime_video_overlay_bridge.dart';
import 'package:surveycam/features/overlay/domain/overlay_model.dart';
import 'package:surveycam/features/overlay/domain/overlay_render_snapshot.dart';
import 'package:surveycam/features/overlay/domain/overlay_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('frame geometry accepts CameraX display metadata', () {
    final geometry = RealtimeOverlayFrameGeometry.fromMap(
      const <Object?, Object?>{
        'width': 1920,
        'height': 1080,
        'rotationDegrees': 90,
        'mirrored': true,
      },
    );

    expect(geometry.isValid, isTrue);
    expect(geometry.width, 1920);
    expect(geometry.height, 1080);
    expect(geometry.rotationDegrees, 90);
    expect(geometry.mirrored, isTrue);
  });

  test('zero sized CameraX geometry is rejected', () {
    final geometry = RealtimeOverlayFrameGeometry.fromMap(
      const <Object?, Object?>{
        'width': 0,
        'height': 1080,
      },
    );

    expect(geometry.isValid, isFalse);
  });

  test('segment applied status is independent from strict native health',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('surveycam/realtime_video_overlay');
    var status = <String, Object?>{
      'renderedFrames': 4,
      'errorSinceEnable': false,
    };

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'isSupported':
        case 'arm':
        case 'setEnabled':
          return true;
        case 'getStatus':
          return status;
        case 'clear':
        case 'disarm':
          return null;
      }
      return null;
    });

    try {
      final bridge = RealtimeVideoOverlayBridge();
      expect(await bridge.arm(), isTrue);
      expect(await bridge.activate(), isTrue);
      expect(await bridge.confirmCurrentSegmentApplied(), isTrue);

      status = <String, Object?>{
        'renderedFrames': 4,
        'errorSinceEnable': true,
      };
      final unhealthyReport = await bridge.inspectCurrentSegment();
      expect(unhealthyReport.applied, isTrue);
      expect(unhealthyReport.healthy, isFalse);

      status = <String, Object?>{
        'renderedFrames': 0,
        'errorSinceEnable': false,
      };
      expect(await bridge.confirmCurrentSegmentApplied(), isFalse);
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });
  test('mirror mismatch requests one builder-time VideoCapture rebuild',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('surveycam/realtime_video_overlay');
    var matchesRequested = false;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'setFrontVideoMirroring':
          return matchesRequested;
        case 'getCaptureTransformStatus':
          return <String, Object?>{
            'videoCaptureRegistered': true,
            'frontVideoMirrorEnabled': true,
            'matchesRequestedMirrorMode': matchesRequested,
          };
      }
      return null;
    });

    try {
      final bridge = RealtimeVideoOverlayBridge();
      expect(await bridge.configureFrontVideoMirroring(true), isFalse);
      expect(await bridge.requiresFrontVideoMirrorRebuild(true), isTrue);

      matchesRequested = true;
      expect(await bridge.configureFrontVideoMirroring(true), isTrue);
      expect(await bridge.requiresFrontVideoMirrorRebuild(true), isFalse);
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test(
      'strict health distinguishes applied overlay from latest-generation health',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('surveycam/realtime_video_overlay');
    var status = <String, Object?>{
      'armed': true,
      'enabled': true,
      'renderedFrames': 0,
      'errorSinceEnable': false,
      'overlayGeneration': 2,
      'renderedOverlayGeneration': 1,
    };

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'isSupported':
        case 'arm':
        case 'setEnabled':
          return true;
        case 'getStatus':
          return status;
        case 'clear':
        case 'disarm':
          return null;
      }
      return null;
    });

    try {
      final bridge = RealtimeVideoOverlayBridge();
      expect(await bridge.arm(), isTrue);
      expect(await bridge.activate(), isTrue);

      status = <String, Object?>{
        'armed': true,
        'enabled': true,
        'renderedFrames': 12,
        'errorSinceEnable': false,
        'overlayGeneration': 3,
        'renderedOverlayGeneration': 2,
      };
      var report = await bridge.inspectCurrentSegment();
      expect(report.applied, isTrue);
      expect(report.healthy, isFalse);
      expect(report.reason, 'latest_overlay_generation_not_rendered');

      status = <String, Object?>{
        'armed': true,
        'enabled': true,
        'renderedFrames': 13,
        'errorSinceEnable': false,
        'overlayGeneration': 3,
        'renderedOverlayGeneration': 3,
      };
      report = await bridge.inspectCurrentSegment();
      expect(report.applied, isTrue);
      expect(report.healthy, isTrue);
      expect(report.reason, isNull);
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('Phase 7.1 prebind handshake prepares raster before start verification',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('surveycam/realtime_video_overlay');
    final calls = <String>[];
    var overlayGeneration = 0;
    var enabled = false;
    var recordingMarked = false;
    var statusPollsAfterStart = 0;
    String? handshakeCaptureOrientation;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'isSupported':
        case 'arm':
          return true;
        case 'beginHandshake':
          handshakeCaptureOrientation =
              (call.arguments as Map?)?['captureOrientation'] as String?;
          return true;
        case 'getFrameGeometry':
          return <String, Object?>{
            'width': 1080,
            'height': 1920,
            'rotationDegrees': 90,
            'mirrored': false,
          };
        case 'setOverlayPng':
          overlayGeneration = 1;
          return true;
        case 'consumeLastError':
          return null;
        case 'setEnabled':
          enabled = call.arguments is Map &&
              (call.arguments as Map)['enabled'] == true;
          return enabled;
        case 'markRecordingStarted':
          recordingMarked = true;
          statusPollsAfterStart = 0;
          return null;
        case 'getStatus':
          if (recordingMarked) {
            statusPollsAfterStart++;
          }
          final rendered = recordingMarked && statusPollsAfterStart >= 2;
          return <String, Object?>{
            'armed': true,
            'enabled': enabled,
            'renderedFrames': rendered ? 1 : 0,
            'errorSinceEnable': false,
            'overlayGeneration': overlayGeneration,
            'uploadedOverlayGeneration': overlayGeneration,
            'renderedOverlayGeneration': rendered ? overlayGeneration : 0,
          };
        case 'cancelHandshake':
        case 'clear':
        case 'disarm':
          return null;
      }
      return null;
    });

    const snapshot = OverlayRenderSnapshot(
      data: OverlayData(
        dateTime: '2026-09-09 18:06:05',
        latitude: 20.1,
        longitude: 85.2,
        altitude: 10,
        heading: 0,
        direction: 'N',
        note: 'Phase 7.1',
      ),
      settings: OverlaySettings(),
      orientation: DeviceOrientation.portraitUp,
    );

    try {
      final bridge = RealtimeVideoOverlayBridge(
        rasterizer: ({
          required OverlayRenderSnapshot snapshot,
          required int width,
          required int height,
          double? viewportAspectRatio,
        }) async {
          expect(width, greaterThan(0));
          expect(height, greaterThan(0));
          return Uint8List.fromList(<int>[1, 2, 3]);
        },
      );

      expect(
        await bridge.prepare(
          snapshot,
          viewportAspectRatio: 16 / 9,
          captureOrientation: DeviceOrientation.landscapeLeft,
        ),
        isTrue,
      );
      expect(bridge.isActive, isFalse);
      expect(handshakeCaptureOrientation, 'landscapeLeft');
      expect(
        calls.indexOf('beginHandshake'),
        lessThan(calls.indexOf('getFrameGeometry')),
      );
      expect(
        calls.indexOf('getFrameGeometry'),
        lessThan(calls.indexOf('setOverlayPng')),
      );
      expect(
        calls.indexOf('setOverlayPng'),
        lessThan(calls.indexOf('setEnabled')),
      );

      expect(await bridge.activate(), isTrue);
      expect(bridge.isActive, isTrue);
      expect(
        calls.indexOf('markRecordingStarted'),
        greaterThan(calls.indexOf('setEnabled')),
      );
      expect(statusPollsAfterStart, greaterThanOrEqualTo(2));
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('stop cleanup cancels an in-flight Phase 7.1 activation', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('surveycam/realtime_video_overlay');
    var overlayGeneration = 0;
    var enabled = false;
    var recordingMarked = false;
    final activationStatusRequested = Completer<void>();
    final activationStatusResponse = Completer<Map<String, Object?>>();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'isSupported':
        case 'arm':
        case 'beginHandshake':
          return true;
        case 'getFrameGeometry':
          return <String, Object?>{
            'width': 1080,
            'height': 1920,
            'rotationDegrees': 90,
            'mirrored': false,
          };
        case 'setOverlayPng':
          overlayGeneration = 1;
          return true;
        case 'consumeLastError':
          return null;
        case 'setEnabled':
          enabled = call.arguments is Map &&
              (call.arguments as Map)['enabled'] == true;
          return enabled;
        case 'markRecordingStarted':
          recordingMarked = true;
          return null;
        case 'getStatus':
          if (recordingMarked) {
            if (!activationStatusRequested.isCompleted) {
              activationStatusRequested.complete();
            }
            return activationStatusResponse.future;
          }
          return <String, Object?>{
            'armed': true,
            'enabled': enabled,
            'renderedFrames': 0,
            'errorSinceEnable': false,
            'overlayGeneration': overlayGeneration,
            'uploadedOverlayGeneration': overlayGeneration,
            'renderedOverlayGeneration': 0,
          };
        case 'cancelHandshake':
        case 'clear':
        case 'disarm':
          return null;
      }
      return null;
    });

    const snapshot = OverlayRenderSnapshot(
      data: OverlayData(
        dateTime: '2026-09-09 18:06:05',
        latitude: 20.1,
        longitude: 85.2,
        altitude: 10,
        heading: 0,
        direction: 'N',
        note: 'Stop race',
      ),
      settings: OverlaySettings(),
      orientation: DeviceOrientation.portraitUp,
    );

    try {
      final bridge = RealtimeVideoOverlayBridge(
        rasterizer: ({
          required OverlayRenderSnapshot snapshot,
          required int width,
          required int height,
          double? viewportAspectRatio,
        }) async =>
            Uint8List.fromList(<int>[1, 2, 3]),
      );

      expect(await bridge.prepare(snapshot), isTrue);
      final activationFuture = bridge.activate();
      await activationStatusRequested.future;

      final finishFuture = bridge.finish();
      await Future<void>.delayed(Duration.zero);
      activationStatusResponse.complete(<String, Object?>{
        'armed': true,
        'enabled': true,
        'renderedFrames': 1,
        'errorSinceEnable': false,
        'overlayGeneration': 1,
        'uploadedOverlayGeneration': 1,
        'renderedOverlayGeneration': 1,
      });

      await finishFuture;
      expect(await activationFuture, isFalse);
      expect(bridge.isActive, isFalse);
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('physical orientation rebuilds HUD without transforming camera GPU',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('surveycam/realtime_video_overlay');
    final calls = <MethodCall>[];
    final rasterOrientations = <DeviceOrientation>[];
    var generation = 0;
    var enabled = false;
    var recordingMarked = false;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'isSupported':
        case 'arm':
        case 'beginHandshake':
          return true;
        case 'getFrameGeometry':
          return <String, Object?>{
            'width': 1080,
            'height': 1920,
            'rotationDegrees': 0,
            'mirrored': false,
          };
        case 'setOverlayPng':
          generation++;
          return true;
        case 'setEnabled':
          enabled = (call.arguments as Map?)?['enabled'] == true;
          return enabled;
        case 'markRecordingStarted':
          recordingMarked = true;
          return null;
        case 'getStatus':
          return <String, Object?>{
            'armed': true,
            'enabled': enabled,
            'renderedFrames': recordingMarked ? 1 : 0,
            'errorSinceEnable': false,
            'overlayGeneration': generation,
            'uploadedOverlayGeneration': generation,
            'renderedOverlayGeneration': recordingMarked ? generation : 0,
            'overlayLayoutOrientation':
                generation > 1 ? 'landscapeLeft' : 'portraitUp',
            'uploadedOverlayLayoutOrientation':
                generation > 1 ? 'landscapeLeft' : 'portraitUp',
            'cameraTransformMode': 'cameraxBasePassThrough',
            'dynamicScaleMode': 'none',
          };
        case 'consumeLastError':
          return null;
        case 'cancelHandshake':
        case 'clear':
        case 'releaseHandshakePrebind':
        case 'disarm':
          return null;
      }
      return null;
    });

    const portrait = OverlayRenderSnapshot(
      data: OverlayData(
        dateTime: '2026-09-10 10:00:00',
        latitude: 20.1,
        longitude: 85.2,
        altitude: 10,
        heading: 0,
        direction: 'N',
        note: 'Pass-through',
      ),
      settings: OverlaySettings(),
      orientation: DeviceOrientation.portraitUp,
    );
    const landscape = OverlayRenderSnapshot(
      data: OverlayData(
        dateTime: '2026-09-10 10:00:00',
        latitude: 20.1,
        longitude: 85.2,
        altitude: 10,
        heading: 0,
        direction: 'N',
        note: 'Pass-through',
      ),
      settings: OverlaySettings(),
      orientation: DeviceOrientation.landscapeLeft,
    );

    try {
      final bridge = RealtimeVideoOverlayBridge(
        rasterizer: ({
          required OverlayRenderSnapshot snapshot,
          required int width,
          required int height,
          double? viewportAspectRatio,
        }) async {
          rasterOrientations.add(snapshot.orientation);
          return Uint8List.fromList(<int>[1, 2, 3]);
        },
      );

      expect(
        await bridge.prepare(
          portrait,
          viewportAspectRatio: 9 / 16,
        ),
        isTrue,
      );
      expect(await bridge.activate(), isTrue);

      bridge.update(
        landscape,
        viewportAspectRatio: 16 / 9,
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(rasterOrientations, <DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
      ]);
      final overlayCalls =
          calls.where((call) => call.method == 'setOverlayPng').toList();
      expect(overlayCalls, hasLength(2));
      expect(
        overlayCalls
            .map((call) => (call.arguments as Map)['orientation'])
            .toList(),
        <Object?>['portraitUp', 'landscapeLeft'],
      );

      // Phase 7.2.3 intentionally does not send a dynamic camera-transform
      // command. CameraX owns camera pixels for the whole recording.
      expect(
        calls.where((call) => call.method == 'setDynamicOrientation'),
        isEmpty,
      );
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('stop freeze cancels an in-flight orientation HUD raster', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('surveycam/realtime_video_overlay');
    final calls = <MethodCall>[];
    var generation = 0;
    var enabled = false;
    var recordingMarked = false;
    var rasterCall = 0;
    final secondRasterStarted = Completer<void>();
    final secondRaster = Completer<Uint8List?>();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'isSupported':
        case 'arm':
        case 'beginHandshake':
          return true;
        case 'getFrameGeometry':
          return <String, Object?>{
            'width': 1080,
            'height': 1920,
            'rotationDegrees': 0,
            'mirrored': false,
          };
        case 'setOverlayPng':
          generation++;
          return true;
        case 'setEnabled':
          enabled = (call.arguments as Map?)?['enabled'] == true;
          return enabled;
        case 'markRecordingStarted':
          recordingMarked = true;
          return null;
        case 'getStatus':
          return <String, Object?>{
            'armed': true,
            'enabled': enabled,
            'renderedFrames': recordingMarked ? 1 : 0,
            'errorSinceEnable': false,
            'overlayGeneration': generation,
            'uploadedOverlayGeneration': generation,
            'renderedOverlayGeneration': recordingMarked ? generation : 0,
            'overlayLayoutOrientation': 'portraitUp',
            'uploadedOverlayLayoutOrientation': 'portraitUp',
            'cameraTransformMode': 'cameraxBasePassThrough',
            'dynamicScaleMode': 'none',
          };
        case 'consumeLastError':
          return null;
        case 'cancelHandshake':
        case 'clear':
        case 'releaseHandshakePrebind':
        case 'disarm':
          return null;
      }
      return null;
    });

    const portrait = OverlayRenderSnapshot(
      data: OverlayData(
        dateTime: '2026-09-10 12:00:00',
        latitude: 20.1,
        longitude: 85.2,
        altitude: 10,
        heading: 0,
        direction: 'N',
        note: 'Freeze',
      ),
      settings: OverlaySettings(),
      orientation: DeviceOrientation.portraitUp,
    );
    const landscape = OverlayRenderSnapshot(
      data: OverlayData(
        dateTime: '2026-09-10 12:00:01',
        latitude: 20.1,
        longitude: 85.2,
        altitude: 10,
        heading: 0,
        direction: 'N',
        note: 'Freeze',
      ),
      settings: OverlaySettings(),
      orientation: DeviceOrientation.landscapeLeft,
    );

    try {
      final bridge = RealtimeVideoOverlayBridge(
        rasterizer: ({
          required OverlayRenderSnapshot snapshot,
          required int width,
          required int height,
          double? viewportAspectRatio,
        }) {
          rasterCall++;
          if (rasterCall == 1) {
            return Future<Uint8List?>.value(
              Uint8List.fromList(<int>[1, 2, 3]),
            );
          }
          if (!secondRasterStarted.isCompleted) {
            secondRasterStarted.complete();
          }
          return secondRaster.future;
        },
      );

      expect(await bridge.prepare(portrait), isTrue);
      expect(await bridge.activate(), isTrue);

      bridge.update(landscape, viewportAspectRatio: 16 / 9);
      await secondRasterStarted.future;
      await bridge.freezeUpdatesForStop();
      secondRaster.complete(Uint8List.fromList(<int>[4, 5, 6]));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        calls.where((call) => call.method == 'setOverlayPng').length,
        1,
      );
      expect(
        calls.where((call) => call.method == 'setDynamicOrientation'),
        isEmpty,
      );
      final report = await bridge.inspectCurrentSegment();
      expect(report.applied, isTrue);
      // Stop deliberately cancelled the new landscape HUD before it reached
      // native. The segment must not be promoted to instant-save healthy while
      // its final physical orientation is represented by the older portrait HUD.
      expect(report.healthy, isFalse);
      expect(report.reason, 'latest_overlay_orientation_not_uploaded');
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('rapid physical turns commit only the newest completed HUD raster',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('surveycam/realtime_video_overlay');
    final calls = <MethodCall>[];
    final rasterOrientations = <DeviceOrientation>[];
    var generation = 0;
    var enabled = false;
    var recordingMarked = false;
    var rasterCall = 0;
    final secondRasterStarted = Completer<void>();
    final releaseSecondRaster = Completer<Uint8List?>();
    final thirdRasterStarted = Completer<void>();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'isSupported':
        case 'arm':
        case 'beginHandshake':
          return true;
        case 'getFrameGeometry':
          return <String, Object?>{
            'width': 1080,
            'height': 1920,
            'rotationDegrees': 0,
            'mirrored': false,
          };
        case 'setOverlayPng':
          generation++;
          return true;
        case 'setEnabled':
          enabled = (call.arguments as Map?)?['enabled'] == true;
          return enabled;
        case 'markRecordingStarted':
          recordingMarked = true;
          return null;
        case 'getStatus':
          return <String, Object?>{
            'armed': true,
            'enabled': enabled,
            'renderedFrames': recordingMarked ? 1 : 0,
            'errorSinceEnable': false,
            'overlayGeneration': generation,
            'uploadedOverlayGeneration': generation,
            'renderedOverlayGeneration': recordingMarked ? generation : 0,
            'overlayLayoutOrientation':
                generation > 1 ? 'landscapeRight' : 'portraitUp',
            'uploadedOverlayLayoutOrientation':
                generation > 1 ? 'landscapeRight' : 'portraitUp',
            'cameraTransformMode': 'cameraxBasePassThrough',
            'dynamicScaleMode': 'none',
          };
        case 'consumeLastError':
          return null;
        case 'cancelHandshake':
        case 'clear':
        case 'releaseHandshakePrebind':
        case 'disarm':
          return null;
      }
      return null;
    });

    const portrait = OverlayRenderSnapshot(
      data: OverlayData(
        dateTime: '2026-09-10 13:00:00',
        latitude: 20.1,
        longitude: 85.2,
        altitude: 10,
        heading: 0,
        direction: 'N',
        note: 'Rapid orientation',
      ),
      settings: OverlaySettings(),
      orientation: DeviceOrientation.portraitUp,
    );
    const landscapeLeft = OverlayRenderSnapshot(
      data: OverlayData(
        dateTime: '2026-09-10 13:00:00',
        latitude: 20.1,
        longitude: 85.2,
        altitude: 10,
        heading: 0,
        direction: 'N',
        note: 'Rapid orientation',
      ),
      settings: OverlaySettings(),
      orientation: DeviceOrientation.landscapeLeft,
    );
    const landscapeRight = OverlayRenderSnapshot(
      data: OverlayData(
        dateTime: '2026-09-10 13:00:00',
        latitude: 20.1,
        longitude: 85.2,
        altitude: 10,
        heading: 0,
        direction: 'N',
        note: 'Rapid orientation',
      ),
      settings: OverlaySettings(),
      orientation: DeviceOrientation.landscapeRight,
    );

    try {
      final bridge = RealtimeVideoOverlayBridge(
        rasterizer: ({
          required OverlayRenderSnapshot snapshot,
          required int width,
          required int height,
          double? viewportAspectRatio,
        }) {
          rasterCall++;
          rasterOrientations.add(snapshot.orientation);
          if (rasterCall == 1) {
            return Future<Uint8List?>.value(
              Uint8List.fromList(<int>[1, 2, 3]),
            );
          }
          if (rasterCall == 2) {
            if (!secondRasterStarted.isCompleted) {
              secondRasterStarted.complete();
            }
            return releaseSecondRaster.future;
          }
          if (!thirdRasterStarted.isCompleted) {
            thirdRasterStarted.complete();
          }
          return Future<Uint8List?>.value(Uint8List.fromList(<int>[7, 8, 9]));
        },
      );

      expect(await bridge.prepare(portrait), isTrue);
      expect(await bridge.activate(), isTrue);

      bridge.update(landscapeLeft, viewportAspectRatio: 16 / 9);
      await secondRasterStarted.future;
      bridge.update(landscapeRight, viewportAspectRatio: 16 / 9);
      releaseSecondRaster.complete(Uint8List.fromList(<int>[4, 5, 6]));
      await thirdRasterStarted.future;
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(rasterOrientations, <DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      final committedOrientations = calls
          .where((call) => call.method == 'setOverlayPng')
          .map((call) => (call.arguments as Map)['orientation'])
          .toList();
      expect(
        committedOrientations,
        <Object?>['portraitUp', 'landscapeRight'],
      );
      expect(
        calls.where((call) => call.method == 'setDynamicOrientation'),
        isEmpty,
      );
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('production health rejects a rendered HUD with stale orientation',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('surveycam/realtime_video_overlay');
    var generation = 0;
    var enabled = false;
    var recordingMarked = false;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'isSupported':
        case 'arm':
        case 'beginHandshake':
          return true;
        case 'getFrameGeometry':
          return <String, Object?>{
            'width': 1080,
            'height': 1920,
            'rotationDegrees': 0,
            'mirrored': false,
          };
        case 'setOverlayPng':
          generation++;
          return true;
        case 'setEnabled':
          enabled = (call.arguments as Map?)?['enabled'] == true;
          return enabled;
        case 'markRecordingStarted':
          recordingMarked = true;
          return null;
        case 'getStatus':
          return <String, Object?>{
            'armed': true,
            'enabled': enabled,
            'renderedFrames': recordingMarked ? 2 : 0,
            'errorSinceEnable': false,
            'overlayGeneration': generation,
            'uploadedOverlayGeneration': generation,
            'renderedOverlayGeneration': recordingMarked ? generation : 0,
            'overlayLayoutOrientation':
                generation > 1 ? 'landscapeLeft' : 'portraitUp',
            // Deliberately stale: certification must not instant-save this.
            'uploadedOverlayLayoutOrientation': 'portraitUp',
            'cameraTransformMode': 'cameraxBasePassThrough',
            'dynamicScaleMode': 'none',
          };
        case 'consumeLastError':
          return null;
      }
      return null;
    });

    const portrait = OverlayRenderSnapshot(
      data: OverlayData(
        dateTime: '2026-09-10 14:00:00',
        latitude: 20.1,
        longitude: 85.2,
        altitude: 10,
        heading: 0,
        direction: 'N',
        note: 'Health',
      ),
      settings: OverlaySettings(),
      orientation: DeviceOrientation.portraitUp,
    );
    const landscape = OverlayRenderSnapshot(
      data: OverlayData(
        dateTime: '2026-09-10 14:00:00',
        latitude: 20.1,
        longitude: 85.2,
        altitude: 10,
        heading: 0,
        direction: 'N',
        note: 'Health',
      ),
      settings: OverlaySettings(),
      orientation: DeviceOrientation.landscapeLeft,
    );

    try {
      final bridge = RealtimeVideoOverlayBridge(
        rasterizer: ({
          required OverlayRenderSnapshot snapshot,
          required int width,
          required int height,
          double? viewportAspectRatio,
        }) async =>
            Uint8List.fromList(<int>[1, 2, 3]),
      );

      expect(await bridge.prepare(portrait), isTrue);
      expect(await bridge.activate(), isTrue);
      bridge.update(landscape, viewportAspectRatio: 16 / 9);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final report = await bridge.inspectCurrentSegment();
      expect(report.applied, isTrue);
      expect(report.healthy, isFalse);
      expect(report.reason, 'latest_overlay_orientation_not_uploaded');
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test(
      'front video portrait-to-landscape update half-turns HUD without changing portrait',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('surveycam/realtime_video_overlay');
    final rasterOrientations = <DeviceOrientation>[];
    final uploadedOrientations = <String>[];
    var generation = 0;
    var enabled = false;
    var recordingStarted = false;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'isSupported':
        case 'arm':
        case 'beginHandshake':
          return true;
        case 'getFrameGeometry':
          return <String, Object?>{
            'width': 1080,
            'height': 1920,
            'rotationDegrees': 0,
            'mirrored': true,
          };
        case 'setOverlayPng':
          generation++;
          uploadedOrientations.add(
            (call.arguments as Map)['orientation'] as String,
          );
          return true;
        case 'consumeLastError':
          return null;
        case 'setEnabled':
          enabled = (call.arguments as Map?)?['enabled'] == true;
          return enabled;
        case 'markRecordingStarted':
          recordingStarted = true;
          return null;
        case 'getStatus':
          return <String, Object?>{
            'armed': true,
            'enabled': enabled,
            'renderedFrames': recordingStarted ? 2 : 0,
            'errorSinceEnable': false,
            'overlayGeneration': generation,
            'uploadedOverlayGeneration': generation,
            'renderedOverlayGeneration': recordingStarted ? generation : 0,
            'overlayLayoutOrientation':
                uploadedOrientations.isEmpty ? null : uploadedOrientations.last,
            'uploadedOverlayLayoutOrientation':
                uploadedOrientations.isEmpty ? null : uploadedOrientations.last,
            'cameraTransformMode': 'cameraxBasePassThrough',
            'dynamicScaleMode': 'none',
          };
        case 'clear':
        case 'disarm':
        case 'cancelHandshake':
          return null;
      }
      return null;
    });

    const portrait = OverlayRenderSnapshot(
      data: OverlayData(
        dateTime: '2026-09-11 22:33:31',
        latitude: 20.685613,
        longitude: 86.647966,
        altitude: -52.1,
        heading: 0,
        direction: 'N',
        note: 'Front landscape regression',
      ),
      settings: OverlaySettings(),
      orientation: DeviceOrientation.portraitUp,
    );
    final landscapeLeft = OverlayRenderSnapshot(
      data: portrait.data,
      settings: portrait.settings,
      orientation: DeviceOrientation.landscapeLeft,
    );

    try {
      final bridge = RealtimeVideoOverlayBridge(
        rasterizer: ({
          required OverlayRenderSnapshot snapshot,
          required int width,
          required int height,
          double? viewportAspectRatio,
        }) async {
          rasterOrientations.add(snapshot.orientation);
          return Uint8List.fromList(<int>[1, 2, 3]);
        },
      );

      expect(
        await bridge.prepare(
          portrait,
          viewportAspectRatio: 9 / 16,
          captureOrientation: DeviceOrientation.portraitUp,
          isFrontCamera: true,
        ),
        isTrue,
      );
      expect(await bridge.activate(), isTrue);

      bridge.update(
        landscapeLeft,
        viewportAspectRatio: 16 / 9,
        isFrontCamera: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(
        rasterOrientations,
        containsAllInOrder(<DeviceOrientation>[
          DeviceOrientation.portraitUp,
          DeviceOrientation.landscapeRight,
        ]),
      );
      expect(uploadedOrientations.first, 'portraitUp');
      expect(uploadedOrientations.last, 'landscapeRight');

      bridge.update(
        portrait,
        viewportAspectRatio: 9 / 16,
        isFrontCamera: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(rasterOrientations.last, DeviceOrientation.portraitUp);
      expect(uploadedOrientations.last, 'portraitUp');
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

}
