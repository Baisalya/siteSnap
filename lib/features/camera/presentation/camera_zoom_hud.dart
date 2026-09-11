import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Lightweight zoom feedback that stays independent from the camera preview
/// rebuild cadence. The camera follows the user's fingers through CameraX,
/// while this HUD can repaint at gesture speed without rebuilding the preview.
class CameraZoomHud extends StatelessWidget {
  const CameraZoomHud({
    super.key,
    required this.zoom,
    required this.minZoom,
    required this.maxZoom,
    required this.isGestureActive,
    required this.onReset,
  });

  final double zoom;
  final double minZoom;
  final double maxZoom;
  final bool isGestureActive;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final clampedZoom = zoom.clamp(minZoom, maxZoom).toDouble();
    final progress = _displayProgress(clampedZoom, minZoom, maxZoom);

    return RepaintBoundary(
      child: Semantics(
        button: true,
        label: 'Zoom ${clampedZoom.toStringAsFixed(1)} times. Tap to reset.',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onReset,
          child: AnimatedScale(
            scale: isGestureActive ? 1.06 : 1,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 7),
              decoration: BoxDecoration(
                color: Colors.black.withValues(
                  alpha: isGestureActive ? 0.78 : 0.68,
                ),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Colors.white.withValues(
                    alpha: isGestureActive ? 0.9 : 0.68,
                  ),
                ),
                boxShadow: isGestureActive
                    ? <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ]
                    : const <BoxShadow>[],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 48,
                    child: _ZoomText(zoom: clampedZoom),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 112,
                    height: 18,
                    child: _ZoomRuler(
                      progress: progress,
                      isGestureActive: isGestureActive,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Ratio-based pinch zoom is multiplicative, so a logarithmic display track
  /// gives useful visual travel at the lower zoom ratios instead of compressing
  /// the 1x-2x region when a device exposes a large digital max zoom.
  static double _displayProgress(
    double zoom,
    double minZoom,
    double maxZoom,
  ) {
    if (!minZoom.isFinite || !maxZoom.isFinite || maxZoom <= minZoom) {
      return 0;
    }
    final safeMin = math.max(0.01, minZoom);
    final safeMax = math.max(safeMin, maxZoom);
    final safeZoom = zoom.clamp(safeMin, safeMax).toDouble();
    final denominator = math.log(safeMax) - math.log(safeMin);
    if (denominator.abs() < 0.000001) return 0;
    return ((math.log(safeZoom) - math.log(safeMin)) / denominator)
        .clamp(0.0, 1.0)
        .toDouble();
  }
}

class _ZoomText extends StatelessWidget {
  const _ZoomText({required this.zoom});

  final double zoom;

  @override
  Widget build(BuildContext context) {
    // The number itself follows the gesture directly. AnimatedSwitcher on every
    // 0.1x label change creates overlapping fades/scales during a fast pinch and
    // looks like visual stutter even when CameraX is moving correctly.
    return Text(
      '${zoom.toStringAsFixed(1)}x',
      textAlign: TextAlign.center,
      maxLines: 1,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _ZoomRuler extends StatelessWidget {
  const _ZoomRuler({
    required this.progress,
    required this.isGestureActive,
  });

  final double progress;
  final bool isGestureActive;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _ZoomRulerPainter(isGestureActive: isGestureActive),
          ),
        ),
        if (isGestureActive)
          Align(
            alignment: Alignment((progress * 2) - 1, 0),
            child: _ZoomThumb(isGestureActive: true),
          )
        else
          AnimatedAlign(
            alignment: Alignment((progress * 2) - 1, 0),
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            child: const _ZoomThumb(isGestureActive: false),
          ),
      ],
    );
  }
}

class _ZoomThumb extends StatelessWidget {
  const _ZoomThumb({required this.isGestureActive});

  final bool isGestureActive;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      width: isGestureActive ? 8 : 7,
      height: isGestureActive ? 8 : 7,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.3),
          width: 0.7,
        ),
      ),
    );
  }
}

class _ZoomRulerPainter extends CustomPainter {
  const _ZoomRulerPainter({required this.isGestureActive});

  final bool isGestureActive;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: isGestureActive ? 0.5 : 0.36)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(1, centerY),
      Offset(size.width - 1, centerY),
      linePaint,
    );

    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: isGestureActive ? 0.75 : 0.52)
      ..strokeWidth = 1;
    for (var i = 0; i <= 6; i++) {
      final x = 1 + ((size.width - 2) * i / 6);
      final tickHeight = (i == 0 || i == 3 || i == 6) ? 7.0 : 4.0;
      canvas.drawLine(
        Offset(x, centerY - (tickHeight / 2)),
        Offset(x, centerY + (tickHeight / 2)),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ZoomRulerPainter oldDelegate) {
    return oldDelegate.isGestureActive != isGestureActive;
  }
}
