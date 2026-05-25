import 'package:flutter/material.dart';
import 'package:surveycam/features/camera/data/CameraState.dart';

class CaptureButton extends StatefulWidget {
  final VoidCallback onCapture;
  final bool isRecording;
  final CameraMode mode;

  const CaptureButton({
    super.key,
    required this.onCapture,
    this.isRecording = false,
    this.mode = CameraMode.photo,
  });

  @override
  State<CaptureButton> createState() => _CaptureButtonState();
}

class _CaptureButtonState extends State<CaptureButton>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  Animation<double>? _outerScale;
  Animation<double>? _innerScale;
  Animation<double>? _pulseOpacity;

  @override
  void initState() {
    super.initState();

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );

    _outerScale = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(
        parent: controller,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );

    _innerScale = Tween<double>(begin: 1.0, end: 0.78).animate(
      CurvedAnimation(
        parent: controller,
        curve: const Interval(0.1, 0.6, curve: Curves.easeOut),
      ),
    );

    _pulseOpacity = Tween<double>(begin: 0.0, end: 0.35).animate(
      CurvedAnimation(
        parent: controller,
        curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
      ),
    );

    _controller = controller;
  }

  void _handleTap() {
    if (_controller == null) return;

    widget.onCapture();

    if (widget.mode == CameraMode.photo) {
      _controller!
          .forward(from: 0)
          .then((_) => mounted ? _controller!.reverse() : null);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // safety guard (avoids LateInitializationError)
    if (_controller == null ||
        _outerScale == null ||
        _innerScale == null ||
        _pulseOpacity == null) {
      return const SizedBox(height: 90, width: 90);
    }

    final Color innerColor =
        widget.mode == CameraMode.video ? Colors.red : Colors.white;

    return SizedBox(
      height: 90,
      width: 90,
      child: GestureDetector(
        onTap: _handleTap,
        child: AnimatedBuilder(
          animation: _controller!,
          builder: (_, __) {
            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // Pulse glow
                Container(
                  height: 82,
                  width: 82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (widget.isRecording ? Colors.red : Colors.white)
                        .withValues(alpha: _pulseOpacity!.value),
                  ),
                ),

                // Outer ring
                Transform.scale(
                  scale: _outerScale!.value,
                  child: Container(
                    height: 72,
                    width: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.transparent,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.8),
                        width: 3.5,
                      ),
                    ),
                  ),
                ),

                // Inner shutter
                Transform.scale(
                  scale: _innerScale!.value,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: widget.isRecording ? 32 : 56,
                    width: widget.isRecording ? 32 : 56,
                    decoration: BoxDecoration(
                      color: innerColor,
                      borderRadius:
                          BorderRadius.circular(widget.isRecording ? 8 : 50),
                      boxShadow: [
                        if (!widget.isRecording)
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
