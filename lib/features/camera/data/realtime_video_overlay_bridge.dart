import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:surveycam/features/camera/domain/realtime_overlay_segment_report.dart';
import 'package:surveycam/features/camera/domain/video_capture_orientation.dart';
import 'package:surveycam/features/overlay/domain/overlay_render_snapshot.dart';
import 'package:surveycam/features/overlay/presentation/video_watermark_processor.dart';

typedef RealtimeOverlayRasterizer = Future<Uint8List?> Function({
  required OverlayRenderSnapshot snapshot,
  required int width,
  required int height,
  double? viewportAspectRatio,
});

class RealtimeOverlayFrameGeometry {
  final int width;
  final int height;
  final int rotationDegrees;
  final bool mirrored;

  const RealtimeOverlayFrameGeometry({
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.mirrored,
  });

  factory RealtimeOverlayFrameGeometry.fromMap(Map<Object?, Object?> map) {
    return RealtimeOverlayFrameGeometry(
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
      rotationDegrees: (map['rotationDegrees'] as num?)?.toInt() ?? 0,
      mirrored: map['mirrored'] as bool? ?? false,
    );
  }

  bool get isValid => width > 0 && height > 0;
}

class RealtimeOverlayNativeStatus {
  final bool armed;
  final bool enabled;
  final int renderedFrames;
  final bool errorSinceEnable;
  final int overlayGeneration;
  final int uploadedOverlayGeneration;
  final int renderedOverlayGeneration;
  final int? lastFrameAgeMs;
  final int? lastRenderedAgeMs;
  final String? lastError;
  final String? overlayLayoutOrientation;
  final String? uploadedOverlayLayoutOrientation;
  final String? cameraTransformMode;
  final String? dynamicScaleMode;

  const RealtimeOverlayNativeStatus({
    required this.armed,
    required this.enabled,
    required this.renderedFrames,
    required this.errorSinceEnable,
    required this.overlayGeneration,
    required this.uploadedOverlayGeneration,
    required this.renderedOverlayGeneration,
    this.lastFrameAgeMs,
    this.lastRenderedAgeMs,
    this.lastError,
    this.overlayLayoutOrientation,
    this.uploadedOverlayLayoutOrientation,
    this.cameraTransformMode,
    this.dynamicScaleMode,
  });

  factory RealtimeOverlayNativeStatus.fromMap(Map<Object?, Object?> map) {
    return RealtimeOverlayNativeStatus(
      armed: map['armed'] as bool? ?? false,
      enabled: map['enabled'] as bool? ?? false,
      renderedFrames: (map['renderedFrames'] as num?)?.toInt() ?? 0,
      errorSinceEnable: map['errorSinceEnable'] as bool? ?? false,
      overlayGeneration: (map['overlayGeneration'] as num?)?.toInt() ?? 0,
      uploadedOverlayGeneration:
          (map['uploadedOverlayGeneration'] as num?)?.toInt() ?? 0,
      renderedOverlayGeneration:
          (map['renderedOverlayGeneration'] as num?)?.toInt() ?? 0,
      lastFrameAgeMs: (map['lastFrameAgeMs'] as num?)?.toInt(),
      lastRenderedAgeMs: (map['lastRenderedAgeMs'] as num?)?.toInt(),
      lastError: map['lastError'] as String?,
      overlayLayoutOrientation: map['overlayLayoutOrientation'] as String?,
      uploadedOverlayLayoutOrientation:
          map['uploadedOverlayLayoutOrientation'] as String?,
      cameraTransformMode: map['cameraTransformMode'] as String?,
      dynamicScaleMode: map['dynamicScaleMode'] as String?,
    );
  }
}

class _PendingRealtimeOverlayUpdate {
  final OverlayRenderSnapshot snapshot;
  final double? viewportAspectRatio;
  final bool urgent;

  const _PendingRealtimeOverlayUpdate(
    this.snapshot,
    this.viewportAspectRatio, {
    this.urgent = false,
  });
}

/// Flutter side of the CameraX realtime overlay bridge.
///
/// Flutter remains the authoring engine for the unified
/// [OverlayRenderSnapshot]. Android's recording-only compositor blends that
/// transparent HUD over CameraX's untouched VideoCapture transform. Data
/// updates are coalesced, while physical orientation changes receive an urgent
/// orientation-aware raster so the GPS card and branding move without ever
/// rescaling the camera image. Flutter's existing CustomPaint remains the
/// preview source of truth; PHOTO/Preview are not driven by this bridge.
///
/// Phase 7/7.1 adds generation/freshness verification. A segment can therefore be
/// known as "overlay applied" without being incorrectly promoted to the
/// stricter "healthy enough for instant save" state.
class RealtimeVideoOverlayBridge {
  static const MethodChannel _channel =
      MethodChannel('surveycam/realtime_video_overlay');
  static const Duration _geometryTimeout = Duration(milliseconds: 1800);
  static const Duration _geometryPollInterval = Duration(milliseconds: 16);
  static const Duration _gpuUploadTimeout = Duration(milliseconds: 900);
  static const Duration _firstRenderTimeout = Duration(milliseconds: 900);
  static const Duration _settleRenderTimeout = Duration(milliseconds: 350);
  static const Duration _stopOrientationFlushTimeout =
      Duration(milliseconds: 180);
  static const Duration _stopOrientationRenderTimeout =
      Duration(milliseconds: 120);
  static const Duration _firstRenderPollInterval = Duration(milliseconds: 16);
  static const Duration _minimumRasterPushInterval =
      Duration(milliseconds: 500);
  static const int _shortEdgePixels = 540;
  static const int _maxLongEdgePixels = 1080;

  bool _supported = false;
  bool _supportChecked = false;
  bool _armed = false;
  bool _active = false;
  bool _draining = false;
  bool _updatesFrozenForStop = false;
  int _updateEpoch = 0;
  Future<void>? _drainFuture;
  _PendingRealtimeOverlayUpdate? _pendingUpdate;
  _PendingRealtimeOverlayUpdate? _preparedUpdate;
  bool _handshakePrepared = false;
  DateTime? _lastRasterPushAt;
  int _updateFailureCount = 0;
  int _consecutiveUpdateFailures = 0;
  int _activationOverlayGeneration = 0;
  OverlayRenderSnapshot? _lastRasterSnapshot;
  double? _lastRasterViewportAspectRatio;
  DeviceOrientation? _recordingStartPhysicalOrientation;
  bool _recordingIsFrontCamera = false;
  DeviceOrientation? _desiredRasterOrientation;
  double? _recordingStartViewportAspectRatio;
  final RealtimeOverlayRasterizer _rasterizer;

  RealtimeVideoOverlayBridge({RealtimeOverlayRasterizer? rasterizer})
      : _rasterizer =
            rasterizer ?? VideoWatermarkProcessor.generateRealtimeOverlayPng;

  bool get isActive => _active;
  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> configureFrontVideoMirroring(bool enabled) async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'setFrontVideoMirroring',
            <String, Object?>{'enabled': enabled},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      debugPrint('CameraX front-video mirror configuration failed: $error');
      return false;
    }
  }

  Future<bool> requiresFrontVideoMirrorRebuild(bool enabled) async {
    if (!_isAndroid) return false;
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getCaptureTransformStatus',
      );
      if (raw == null) return false;
      final registered = raw['videoCaptureRegistered'] as bool? ?? false;
      final matches = raw['matchesRequestedMirrorMode'] as bool? ?? false;
      final requestedEnabled = raw['frontVideoMirrorEnabled'] as bool? ?? false;
      return registered && requestedEnabled == enabled && !matches;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      debugPrint('CameraX mirror rebuild status failed: $error');
      return false;
    }
  }

  Future<bool> arm() async {
    if (!_isAndroid) return false;
    if (!await _isSupported()) return false;
    if (_armed) return true;

    try {
      _armed = await _channel.invokeMethod<bool>('arm') ?? false;
      return _armed;
    } on MissingPluginException {
      _supported = false;
      return false;
    } on PlatformException catch (error) {
      debugPrint('Realtime CameraX overlay arm failed: $error');
      return false;
    }
  }

  /// Pre-binds VideoCapture and prepares the first WYSIWYG raster before the
  /// recorder starts. This avoids the Phase 7 race where geometry was queried
  /// before VideoCapture existed and avoids leaking clean opening frames.
  Future<bool> prepare(
    OverlayRenderSnapshot snapshot, {
    double? viewportAspectRatio,
    DeviceOrientation? captureOrientation,
    bool isFrontCamera = false,
  }) async {
    if (!await arm()) return false;

    try {
      await _quiesceUpdates();
      _preparedUpdate =
          _PendingRealtimeOverlayUpdate(snapshot, viewportAspectRatio);
      _resetSegmentHealth();

      // CameraX capture rotation and physical overlay orientation are separate
      // contracts. The former is frozen for the MP4; the latter remains live
      // and is expressed relative to this start orientation when rasterized.
      _recordingStartPhysicalOrientation = snapshot.orientation;
      _recordingIsFrontCamera = isFrontCamera;
      _desiredRasterOrientation = snapshot.orientation;
      _recordingStartViewportAspectRatio = viewportAspectRatio;
      final targetOrientation = captureOrientation ?? snapshot.orientation;
      _handshakePrepared = await _channel.invokeMethod<bool>(
            'beginHandshake',
            <String, Object?>{'captureOrientation': targetOrientation.name},
          ) ??
          false;
      if (!_handshakePrepared) {
        final reason = await _consumeNativeError();
        debugPrint(
          'Realtime CameraX overlay: handshake prebind failed'
          '${reason == null ? '' : ': $reason'}; using legacy fallback.',
        );
        _preparedUpdate = null;
        await _disableNativeForFallback();
        return false;
      }

      debugPrint(
        'Realtime CameraX overlay: capture orientation=${targetOrientation.name}',
      );
      debugPrint('Realtime CameraX overlay: WAITING_FOR_VIDEO_GEOMETRY');
      final geometry = await _waitForFrameGeometry();
      if (geometry == null) {
        debugPrint(
          'Realtime CameraX overlay: pre-start geometry handshake timed out; using legacy fallback.',
        );
        await _disableNativeForFallback();
        return false;
      }

      debugPrint(
        'Realtime CameraX overlay: geometry '
        '${geometry.width}x${geometry.height} '
        'rotation=${geometry.rotationDegrees} mirror=${geometry.mirrored}',
      );

      final pushed = await _pushSnapshot(
        snapshot,
        geometry: geometry,
        viewportAspectRatio: viewportAspectRatio,
      );
      if (!pushed) {
        debugPrint('Realtime CameraX overlay: initial raster push failed.');
        await _disableNativeForFallback();
        return false;
      }
      _lastRasterSnapshot = snapshot;
      _lastRasterViewportAspectRatio = viewportAspectRatio;

      final status = await _nativeStatus();
      final expectedGeneration = status?.overlayGeneration ?? 0;
      if (expectedGeneration <= 0) {
        debugPrint(
            'Realtime CameraX overlay: native overlay generation missing.');
        await _disableNativeForFallback();
        return false;
      }

      if (!await _waitForUploadedGeneration(expectedGeneration)) {
        debugPrint(
          'Realtime CameraX overlay: GPU texture upload was not confirmed; using legacy fallback.',
        );
        await _disableNativeForFallback();
        return false;
      }
      debugPrint(
        'Realtime CameraX overlay: GPU_TEXTURE_READY generation=$expectedGeneration',
      );

      final enabled = await _channel.invokeMethod<bool>(
            'setEnabled',
            const <String, Object?>{'enabled': true},
          ) ??
          false;
      if (!enabled) {
        debugPrint('Realtime CameraX overlay: native effect refused enable.');
        await _disableNativeForFallback();
        return false;
      }

      _activationOverlayGeneration = expectedGeneration;
      debugPrint(
        'Realtime CameraX overlay: RASTER_READY generation=$expectedGeneration',
      );
      return true;
    } on MissingPluginException {
      _supported = false;
      _active = false;
      _handshakePrepared = false;
      _preparedUpdate = null;
      return false;
    } on PlatformException catch (error) {
      debugPrint('Realtime CameraX overlay prepare failed: $error');
      await _disableNativeForFallback();
      return false;
    }
  }

  /// Verifies a frame rendered after CameraX reported that recording started.
  /// The raster/effect are already ready before the recorder starts, so the
  /// first encoded frame is eligible to contain the overlay.
  Future<bool> activate() async {
    if (!_armed) return false;

    // Preserve the legacy direct activation contract for isolated tests/custom
    // backends that do not use SiteSnap's prepare/start/activate handshake.
    if (!_handshakePrepared || _preparedUpdate == null) {
      try {
        _updateFailureCount = 0;
        _consecutiveUpdateFailures = 0;
        _active = await _channel.invokeMethod<bool>(
              'setEnabled',
              const <String, Object?>{'enabled': true},
            ) ??
            false;
        if (!_active) return false;
        final status = await _nativeStatus();
        _activationOverlayGeneration = status?.overlayGeneration ?? 0;
        return true;
      } catch (error) {
        debugPrint('Realtime CameraX overlay activation failed: $error');
        return false;
      }
    }

    try {
      await _channel.invokeMethod<void>('markRecordingStarted');
      final firstFrameRendered =
          await _waitForRenderedGeneration(_activationOverlayGeneration);
      if (!firstFrameRendered) {
        debugPrint(
          'Realtime CameraX overlay: first recorded overlay frame was not confirmed; using legacy fallback.',
        );
        await _disableNativeForFallback();
        return false;
      }

      // Stop/finish may have cancelled this handshake while the first-frame
      // poll was in flight. Never resurrect the bridge after Stop.
      if (!_handshakePrepared || _preparedUpdate == null || !_armed) {
        return false;
      }

      _active = true;
      _handshakePrepared = false;
      _preparedUpdate = null;
      debugPrint(
        'Realtime CameraX overlay: ACTIVE generation=$_activationOverlayGeneration',
      );
      return true;
    } catch (error) {
      debugPrint('Realtime CameraX overlay activation failed: $error');
      await _disableNativeForFallback();
      return false;
    }
  }

  /// Compatibility entry point for callers that only have an orientation
  /// event. The production CameraViewModel now sends the full overlay snapshot
  /// through [update], but keeping this adapter makes custom backends/tests use
  /// the same stock-camera semantics: camera pixels stay untouched while a new
  /// orientation-aware overlay raster is prepared.
  void updateOrientation(DeviceOrientation orientation) {
    if (!_active || !_isAndroid || _updatesFrozenForStop) return;
    final source = _lastRasterSnapshot ?? _preparedUpdate?.snapshot;
    if (source == null) return;
    update(
      OverlayRenderSnapshot(
        data: source.data,
        settings: source.settings,
        orientation: orientation,
      ),
      viewportAspectRatio: _viewportAspectForPhysicalOrientation(orientation),
    );
  }

  double? _viewportAspectForPhysicalOrientation(
    DeviceOrientation orientation,
  ) {
    final startOrientation = _recordingStartPhysicalOrientation;
    final startAspect = _recordingStartViewportAspectRatio;
    if (startOrientation == null ||
        startAspect == null ||
        !startAspect.isFinite ||
        startAspect <= 0) {
      return startAspect;
    }
    final relative = relativeRecordingOverlayOrientation(
      startOrientation,
      orientation,
    );
    if (relative == DeviceOrientation.landscapeLeft ||
        relative == DeviceOrientation.landscapeRight) {
      return 1 / startAspect;
    }
    return startAspect;
  }

  bool _sameRasterContent(
    OverlayRenderSnapshot snapshot,
    double? viewportAspectRatio,
  ) {
    final previous = _lastRasterSnapshot;
    if (previous == null) return false;
    return previous.orientation == snapshot.orientation &&
        mapEquals(previous.data.toJson(), snapshot.data.toJson()) &&
        mapEquals(previous.settings.toJson(), snapshot.settings.toJson()) &&
        _lastRasterViewportAspectRatio == viewportAspectRatio;
  }

  /// Coalesces location/time/settings changes on the normal 2 FPS budget. A
  /// physical portrait/landscape change is different: it invalidates an older
  /// in-flight raster and becomes an urgent update, bypassing the 500 ms data
  /// throttle. The camera stream itself is never rotated or rescaled.
  void update(
    OverlayRenderSnapshot snapshot, {
    double? viewportAspectRatio,
    bool? isFrontCamera,
  }) {
    if (!_active || _updatesFrozenForStop) return;

    final frontCameraChanged = isFrontCamera != null &&
        isFrontCamera != _recordingIsFrontCamera;
    if (isFrontCamera != null) {
      _recordingIsFrontCamera = isFrontCamera;
    }
    if (!frontCameraChanged &&
        _sameRasterContent(snapshot, viewportAspectRatio)) {
      return;
    }

    final orientationChanged = _desiredRasterOrientation != null &&
        _desiredRasterOrientation != snapshot.orientation;
    _desiredRasterOrientation = snapshot.orientation;
    final urgentGeometryChange = orientationChanged || frontCameraChanged;

    if (urgentGeometryChange) {
      // Invalidate any sleeping/rasterizing data-only update. The drain checks
      // this epoch at <=16 ms intervals while throttled and immediately picks
      // up the newest urgent orientation/lens request.
      _updateEpoch++;
    }

    _pendingUpdate = _PendingRealtimeOverlayUpdate(
      snapshot,
      viewportAspectRatio,
      urgent: urgentGeometryChange,
    );
    if (_draining) return;
    _startDrain();
  }

  void _startDrain() {
    final future = _drainUpdates();
    _drainFuture = future;
    unawaited(future);
  }

  Future<bool> _waitForRasterBudget(int updateEpoch) async {
    final lastPush = _lastRasterPushAt;
    if (lastPush == null) return true;

    var remaining =
        _minimumRasterPushInterval - DateTime.now().difference(lastPush);
    while (remaining > Duration.zero) {
      final slice = remaining > const Duration(milliseconds: 16)
          ? const Duration(milliseconds: 16)
          : remaining;
      await Future<void>.delayed(slice);
      if (!_active || _updatesFrozenForStop || updateEpoch != _updateEpoch) {
        return false;
      }
      remaining =
          _minimumRasterPushInterval - DateTime.now().difference(lastPush);
    }
    return true;
  }

  Future<void> _drainUpdates() async {
    _draining = true;
    try {
      while (_active && !_updatesFrozenForStop && _pendingUpdate != null) {
        final update = _pendingUpdate!;
        final updateEpoch = _updateEpoch;
        _pendingUpdate = null;

        if (!update.urgent && !await _waitForRasterBudget(updateEpoch)) {
          // A newer orientation update intentionally invalidated this work.
          // Loop again so the pending urgent request is not forced to wait for
          // the stale data-update throttle.
          continue;
        }
        if (!_active || _updatesFrozenForStop || updateEpoch != _updateEpoch) {
          continue;
        }

        try {
          final geometry = await _frameGeometry();
          if (_updatesFrozenForStop || updateEpoch != _updateEpoch) {
            continue;
          }
          if (geometry == null) {
            _noteUpdateFailure();
            continue;
          }
          final pushed = await _pushSnapshot(
            update.snapshot,
            geometry: geometry,
            viewportAspectRatio: update.viewportAspectRatio,
            updateEpoch: updateEpoch,
          );
          if (!pushed) {
            if (_updatesFrozenForStop || updateEpoch != _updateEpoch) {
              continue;
            }
            _noteUpdateFailure();
          } else {
            _lastRasterSnapshot = update.snapshot;
            _lastRasterViewportAspectRatio = update.viewportAspectRatio;
            if (update.urgent) {
              final start = _recordingStartPhysicalOrientation;
              final relative = start == null
                  ? DeviceOrientation.portraitUp
                  : relativeRecordingOverlayOrientation(
                      start,
                      update.snapshot.orientation,
                    );
              debugPrint(
                'Realtime CameraX overlay layout: '
                '${update.snapshot.orientation.name} '
                '(relative=${relative.name})',
              );
            }
          }
        } catch (error) {
          if (_updatesFrozenForStop || updateEpoch != _updateEpoch) {
            continue;
          }
          _noteUpdateFailure();
          debugPrint('Realtime CameraX overlay update skipped: $error');
        }
      }
    } finally {
      _draining = false;
      if (_active && !_updatesFrozenForStop && _pendingUpdate != null) {
        _startDrain();
      }
    }
  }

  void _noteUpdateFailure() {
    _updateFailureCount++;
    _consecutiveUpdateFailures++;
  }

  /// Freezes realtime HUD updates for Recorder finalization. A pending physical
  /// orientation update gets one bounded chance to reach an encoded frame; any
  /// work still in flight after that window is invalidated by [_updateEpoch].
  Future<void> freezeUpdatesForStop() async {
    if (_updatesFrozenForStop) return;

    // A normal Stop stays immediate. If the user taps Stop directly after a
    // physical turn, however, give the already-urgent HUD update a very small
    // bounded chance to reach an encoded frame. This mirrors a mature camera
    // UI: the shutter remains responsive without knowingly finalizing the last
    // frames with the previous orientation's card/logo.
    final desiredOrientation = _desiredRasterOrientation;
    final lastCommittedOrientation = _lastRasterSnapshot?.orientation;
    final orientationPending = _active &&
        desiredOrientation != null &&
        lastCommittedOrientation != desiredOrientation;

    if (orientationPending) {
      final drain = _drainFuture;
      if (drain != null) {
        try {
          await Future.any<void>(<Future<void>>[
            drain,
            Future<void>.delayed(_stopOrientationFlushTimeout),
          ]);
        } catch (_) {
          // The production health gate below remains the source of truth.
        }
      }

      if (_lastRasterSnapshot?.orientation == desiredOrientation) {
        try {
          final status = await _nativeStatus();
          if (status != null &&
              status.overlayGeneration > 0 &&
              status.renderedOverlayGeneration < status.overlayGeneration) {
            await _waitForRenderedGeneration(
              status.overlayGeneration,
              timeout: _stopOrientationRenderTimeout,
            );
          }
        } catch (_) {
          // Fall through to freeze; strict certification rejects stale HUDs.
        }
      }
    }

    _updatesFrozenForStop = true;
    _updateEpoch++;
    _pendingUpdate = null;
  }

  Future<RealtimeOverlaySegmentReport> inspectCurrentSegment() async {
    if (!_active || !_supportChecked || !_supported) {
      return const RealtimeOverlaySegmentReport.unavailable();
    }

    try {
      while (_draining || _pendingUpdate != null) {
        final drain = _drainFuture;
        if (drain == null) break;
        await drain;
      }

      var status = await _nativeStatus();
      if (status == null) {
        return RealtimeOverlaySegmentReport.unavailable(
          reason: 'native_overlay_status_missing',
        );
      }

      if (status.overlayGeneration > 0 &&
          status.renderedOverlayGeneration < status.overlayGeneration) {
        await _waitForRenderedGeneration(
          status.overlayGeneration,
          timeout: _settleRenderTimeout,
        );
        status = await _nativeStatus() ?? status;
      }

      final initialGenerationRendered = status.renderedFrames > 0 &&
          status.renderedOverlayGeneration >= _activationOverlayGeneration;
      final latestGenerationRendered = status.overlayGeneration > 0 &&
          status.renderedOverlayGeneration >= status.overlayGeneration;
      final startOrientation = _recordingStartPhysicalOrientation;
      final desiredPhysicalOrientation =
          _desiredRasterOrientation ?? _lastRasterSnapshot?.orientation;
      final expectedLayoutOrientation =
          startOrientation == null || desiredPhysicalOrientation == null
              ? null
              : frontCameraLandscapeVideoOverlayOrientation(
                  relativeOrientation: relativeRecordingOverlayOrientation(
                    startOrientation,
                    desiredPhysicalOrientation,
                  ),
                  physicalOrientation: desiredPhysicalOrientation,
                  isFrontCamera: _recordingIsFrontCamera,
                ).name;
      final latestLayoutUploaded = expectedLayoutOrientation == null ||
          status.uploadedOverlayLayoutOrientation == null ||
          status.uploadedOverlayLayoutOrientation == expectedLayoutOrientation;
      final cameraPassThrough = status.cameraTransformMode == null ||
          status.cameraTransformMode == 'cameraxBasePassThrough';
      final noDynamicCameraScale =
          status.dynamicScaleMode == null || status.dynamicScaleMode == 'none';
      final applied = initialGenerationRendered;
      final healthy = applied &&
          latestGenerationRendered &&
          latestLayoutUploaded &&
          cameraPassThrough &&
          noDynamicCameraScale &&
          !status.errorSinceEnable &&
          _consecutiveUpdateFailures == 0;

      String? reason;
      if (!applied) {
        reason = 'camera_x_overlay_not_rendered';
      } else if (status.errorSinceEnable) {
        reason = status.lastError ?? 'camera_x_overlay_native_error';
      } else if (_consecutiveUpdateFailures > 0) {
        reason = 'overlay_bridge_update_failed';
      } else if (!latestGenerationRendered) {
        reason = 'latest_overlay_generation_not_rendered';
      } else if (!latestLayoutUploaded) {
        reason = 'latest_overlay_orientation_not_uploaded';
      } else if (!cameraPassThrough || !noDynamicCameraScale) {
        reason = 'camera_transform_not_pass_through';
      }

      return RealtimeOverlaySegmentReport(
        applied: applied,
        healthy: healthy,
        renderedFrames: status.renderedFrames,
        overlayGeneration: status.overlayGeneration,
        renderedOverlayGeneration: status.renderedOverlayGeneration,
        updateFailureCount: _updateFailureCount,
        reason: reason,
      );
    } catch (error) {
      debugPrint('Realtime CameraX overlay verification failed: $error');
      return RealtimeOverlaySegmentReport.unavailable(
        reason: 'overlay_verification_failed',
      );
    }
  }

  Future<bool> confirmCurrentSegmentApplied() async =>
      (await inspectCurrentSegment()).applied;

  Future<RealtimeOverlayNativeStatus?> _nativeStatus() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('getStatus');
    if (raw == null) return null;
    return RealtimeOverlayNativeStatus.fromMap(raw);
  }

  Future<void> _disableNativeForFallback() async {
    await _quiesceUpdates();
    _handshakePrepared = false;
    _preparedUpdate = null;
    if (!_supportChecked || !_supported) {
      _armed = false;
      return;
    }
    try {
      await _channel.invokeMethod<void>('cancelHandshake');
      await _channel.invokeMethod<void>(
        'setEnabled',
        const <String, Object?>{'enabled': false},
      );
      await _channel.invokeMethod<void>('clear');
      await _channel.invokeMethod<void>('releaseHandshakePrebind');
      await _channel.invokeMethod<void>('disarm');
    } catch (error) {
      debugPrint('Realtime CameraX overlay fallback cleanup skipped: $error');
    } finally {
      _armed = false;
      _resetSegmentHealth();
    }
  }

  Future<void> finish() async {
    await _quiesceUpdates();
    _handshakePrepared = false;
    _preparedUpdate = null;
    if (!_supportChecked || !_supported) {
      _resetSegmentHealth();
      return;
    }
    try {
      await _channel.invokeMethod<void>('cancelHandshake');
      await _channel.invokeMethod<void>(
        'setEnabled',
        const <String, Object?>{'enabled': false},
      );
      await _channel.invokeMethod<void>('clear');
    } catch (error) {
      debugPrint('Realtime CameraX overlay cleanup skipped: $error');
    } finally {
      _resetSegmentHealth();
    }
  }

  Future<void> disarm() async {
    await finish();
    if (!_armed) return;
    try {
      await _channel.invokeMethod<void>('disarm');
    } catch (_) {
      // Fallback backend remains valid even if native cleanup is unavailable.
    }
    _armed = false;
  }

  Future<void> _quiesceUpdates() async {
    _active = false;
    _updateEpoch++;
    _pendingUpdate = null;

    final drain = _drainFuture;
    if (drain != null) {
      try {
        await drain;
      } catch (error) {
        debugPrint('Realtime CameraX overlay drain cleanup skipped: $error');
      }
    }
    _drainFuture = null;
  }

  void _resetSegmentHealth() {
    _updatesFrozenForStop = false;
    _updateEpoch++;
    _lastRasterPushAt = null;
    _updateFailureCount = 0;
    _consecutiveUpdateFailures = 0;
    _activationOverlayGeneration = 0;
    _lastRasterSnapshot = null;
    _lastRasterViewportAspectRatio = null;
    _recordingStartPhysicalOrientation = null;
    _recordingIsFrontCamera = false;
    _desiredRasterOrientation = null;
    _recordingStartViewportAspectRatio = null;
  }

  Future<bool> _isSupported() async {
    if (_supportChecked) return _supported;
    _supportChecked = true;
    if (!_isAndroid) return false;
    try {
      _supported = await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      _supported = false;
    }
    return _supported;
  }

  Future<RealtimeOverlayFrameGeometry?> _waitForFrameGeometry() async {
    final deadline = DateTime.now().add(_geometryTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final geometry = await _frameGeometry();
      if (geometry != null) return geometry;
      await Future<void>.delayed(_geometryPollInterval);
    }
    return _frameGeometry();
  }

  Future<bool> _waitForUploadedGeneration(int generation) async {
    final deadline = DateTime.now().add(_gpuUploadTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final status = await _nativeStatus();
      if (status != null) {
        if (status.errorSinceEnable) return false;
        if (status.uploadedOverlayGeneration >= generation) return true;
      }
      await Future<void>.delayed(_firstRenderPollInterval);
    }
    final status = await _nativeStatus();
    return status != null &&
        !status.errorSinceEnable &&
        status.uploadedOverlayGeneration >= generation;
  }

  Future<bool> _waitForRenderedGeneration(
    int generation, {
    Duration timeout = _firstRenderTimeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final status = await _nativeStatus();
      if (status != null) {
        if (status.errorSinceEnable) return false;
        if (status.enabled &&
            status.renderedFrames > 0 &&
            status.renderedOverlayGeneration >= generation) {
          return true;
        }
      }
      await Future<void>.delayed(_firstRenderPollInterval);
    }

    final status = await _nativeStatus();
    return status != null &&
        !status.errorSinceEnable &&
        status.enabled &&
        status.renderedFrames > 0 &&
        status.renderedOverlayGeneration >= generation;
  }

  Future<RealtimeOverlayFrameGeometry?> _frameGeometry() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getFrameGeometry',
    );
    if (raw == null) return null;
    final geometry = RealtimeOverlayFrameGeometry.fromMap(raw);
    return geometry.isValid ? geometry : null;
  }

  OverlayRenderSnapshot _rasterSnapshotForPhysicalOrientation(
    OverlayRenderSnapshot snapshot,
  ) {
    final start = _recordingStartPhysicalOrientation ?? snapshot.orientation;
    final relative = relativeRecordingOverlayOrientation(
      start,
      snapshot.orientation,
    );
    final hudOrientation = frontCameraLandscapeVideoOverlayOrientation(
      relativeOrientation: relative,
      physicalOrientation: snapshot.orientation,
      isFrontCamera: _recordingIsFrontCamera,
    );
    return OverlayRenderSnapshot(
      data: snapshot.data,
      settings: snapshot.settings,
      orientation: hudOrientation,
    );
  }

  Future<bool> _pushSnapshot(
    OverlayRenderSnapshot snapshot, {
    required RealtimeOverlayFrameGeometry geometry,
    double? viewportAspectRatio,
    int? updateEpoch,
  }) async {
    final rasterSize = _rasterSizeFor(geometry);
    final rasterSnapshot = _rasterSnapshotForPhysicalOrientation(snapshot);
    final bytes = await _rasterizer(
      snapshot: rasterSnapshot,
      width: rasterSize.$1,
      height: rasterSize.$2,
      viewportAspectRatio: viewportAspectRatio,
    );
    if (bytes == null || bytes.isEmpty) return false;
    if (updateEpoch != null &&
        (_updatesFrozenForStop || updateEpoch != _updateEpoch || !_active)) {
      return false;
    }

    final accepted = await _channel.invokeMethod<bool>(
          'setOverlayPng',
          <String, Object?>{
            'bytes': bytes,
            'orientation': rasterSnapshot.orientation.name,
          },
        ) ??
        false;
    if (!accepted) return false;

    _lastRasterPushAt = DateTime.now();
    _consecutiveUpdateFailures = 0;

    final nativeError = await _consumeNativeError();
    if (nativeError != null) {
      debugPrint('CameraX overlay warning: $nativeError');
    }
    return true;
  }

  Future<String?> _consumeNativeError() async {
    try {
      final error = await _channel.invokeMethod<String>('consumeLastError');
      if (error == null || error.trim().isEmpty) return null;
      return error;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static (int, int) _rasterSizeFor(RealtimeOverlayFrameGeometry geometry) {
    final width = geometry.width.toDouble();
    final height = geometry.height.toDouble();
    final shortEdge = width < height ? width : height;
    if (shortEdge <= 0) return (_shortEdgePixels, _shortEdgePixels);

    var scale = _shortEdgePixels / shortEdge;
    var rasterWidth = (width * scale).round();
    var rasterHeight = (height * scale).round();
    final longEdge = rasterWidth > rasterHeight ? rasterWidth : rasterHeight;
    if (longEdge > _maxLongEdgePixels) {
      scale = _maxLongEdgePixels / (width > height ? width : height);
      rasterWidth = (width * scale).round();
      rasterHeight = (height * scale).round();
    }
    return (
      rasterWidth.clamp(1, _maxLongEdgePixels).toInt(),
      rasterHeight.clamp(1, _maxLongEdgePixels).toInt(),
    );
  }
}
