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

  Future<void> _handleTap() async {
    if (_controller == null) return;

    if (widget.mode == CameraMode.photo) {
      await _controller!.forward();
      await _controller!.reverse();
    }

    widget.onCapture();
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

    final Color innerColor = widget.mode == CameraMode.video ? Colors.red : Colors.white;

    return SizedBox(
      height: 90,
      width: 90,
      child: GestureDetector(
        onTap: _handleTap,
        child: AnimatedBuilder(
          animation: _controller!,
          builder: (_, __) {
            return Transform.scale(
              scale: _outerScale!.value,
              child: Stack(
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
                  Container(
                    height: 72,
                    width: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.transparent,
                      border: Border.all(
                        color: Colors.white,
                        width: 4,
                      ),
                    ),
                  ),

                  // Inner shutter
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: widget.isRecording ? 30 : 52,
                    width: widget.isRecording ? 30 : 52,
                    decoration: BoxDecoration(
                      color: innerColor,
                      borderRadius: BorderRadius.circular(widget.isRecording ? 4 : 50),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
