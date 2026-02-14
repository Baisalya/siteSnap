import 'package:flutter/material.dart';

class CaptureButton extends StatefulWidget {
  final VoidCallback onCapture;

  const CaptureButton({
    super.key,
    required this.onCapture,
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

    await _controller!.forward();
    await _controller!.reverse();

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
                      color: Colors.white
                          .withOpacity(_pulseOpacity!.value),
                    ),
                  ),

                  // Outer ring
                  Container(
                    height: 72,
                    width: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(
                        color: Colors.grey.shade400,
                        width: 4,
                      ),
                    ),
                  ),

                  // Inner shutter
                  Transform.scale(
                    scale: _innerScale!.value,
                    child: Container(
                      height: 52,
                      width: 52,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
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
