import 'package:flutter/material.dart';

class ComparisonSlider extends StatefulWidget {
  final Widget beforeImage;
  final Widget afterImage;

  const ComparisonSlider({
    super.key,
    required this.beforeImage,
    required this.afterImage,
  });

  @override
  State<ComparisonSlider> createState() => _ComparisonSliderState();
}

class _ComparisonSliderState extends State<ComparisonSlider> {
  double _sliderPosition = 0.5; // 0.0 to 1.0

  void _updatePosition(double localDx, double width) {
    setState(() {
      _sliderPosition = (localDx / width).clamp(0.0, 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        return GestureDetector(
          onHorizontalDragUpdate: (details) {
            _updatePosition(details.localPosition.dx, width);
          },
          onTapDown: (details) {
            _updatePosition(details.localPosition.dx, width);
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background (Right side - Usually "After" or "Input" depending on pref)
              // User said: "left (output image) to the right (input image)"
              // So Right Side is Input (Before).
              // We place the Input image at the bottom (visible on the right)
              widget.beforeImage,

              // Foreground (Left side - Output/After)
              // Clipped to show only the left part
              ClipRect(
                clipper: _SliderClipper(_sliderPosition),
                child: widget.afterImage,
              ),

              // The Slider Line
              Positioned(
                left: width * _sliderPosition - 1.5, // Center the 3px line
                top: 0,
                bottom: 0,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 4,
                        offset: const Offset(1, 0),
                      ),
                    ],
                  ),
                ),
              ),

              // The Handle
              Positioned(
                left: width * _sliderPosition - 16, // Center the 32px icon
                top: height / 2 - 16,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.code, // Looks like < >
                    size: 20,
                    color: Colors.indigo,
                  ),
                ),
              ),
              
              // Labels (Optional, but helpful)
              Positioned(
                bottom: 3 * 20,
                left: 20,
                child: Opacity(
                  opacity: _sliderPosition > 0.1 ? 1.0 : _sliderPosition * 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      "Output",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 3 * 20,
                right: 20,
                child: Opacity(
                  opacity: _sliderPosition < 0.9 ? 1.0 : (1.0 - _sliderPosition) * 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      "Input",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SliderClipper extends CustomClipper<Rect> {
  final double factor;

  _SliderClipper(this.factor);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width * factor, size.height);
  }

  @override
  bool shouldReclip(_SliderClipper oldClipper) {
    return oldClipper.factor != factor;
  }
}
