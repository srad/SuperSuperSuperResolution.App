import 'dart:math';
import 'package:flutter/material.dart';

class TileProgressIndicator extends StatelessWidget {
  final int current;
  final int total;
  final String progressMessage;
  final String? statusMessage;
  final double? aspectRatio; // Width / Height

  const TileProgressIndicator({
    super.key,
    required this.current,
    required this.total,
    required this.progressMessage,
    this.statusMessage,
    this.aspectRatio,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF80AB).withValues(alpha: 0.2),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      width: 300, // Fixed width for the popup
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Text(
            "Magic in Progress",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFFF80AB),
                ),
          ),
          const SizedBox(height: 20),

          // The Tile Grid
          Flexible(
            child: AspectRatio(
              aspectRatio: aspectRatio != null 
                  ? (aspectRatio! < 0.5 ? 0.5 : (aspectRatio! > 2.0 ? 2.0 : aspectRatio!))
                  : 1.0,
              child: CustomPaint(
                painter: _GridPainter(
                  current: current,
                  total: total,
                  aspectRatio: aspectRatio ?? 1.0,
                  color: const Color(0xFFFF80AB),
                  emptyColor: const Color(0xFFF8BBD0), // Lighter pink
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Percentage (Big)
          Text(
            progressMessage,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Colors.black87,
            ),
          ),

          if (statusMessage != null) ...[
            // Status Message (Small)
            const SizedBox(height: 8),
            Text(
              statusMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ]
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final int current;
  final int total;
  final double aspectRatio;
  final Color color;
  final Color emptyColor;

  _GridPainter({
    required this.current,
    required this.total,
    required this.aspectRatio,
    required this.color,
    required this.emptyColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0) return;

    // Calculate best grid dimensions to match aspectRatio
    // area = w * h
    // w / h = aspect
    // w = aspect * h
    // tiles = w * h = aspect * h^2
    // h = sqrt(tiles / aspect)
    
    // We want cols * rows >= total
    // cols / rows ~= aspectRatio
    
    int cols = sqrt(total * aspectRatio).ceil();
    int rows = (total / cols).ceil();
    
    // Adjust if we underestimated
    if (cols * rows < total) {
      rows++;
    }

    final double padding = 2.0;
    final double tileW = (size.width - (cols - 1) * padding) / cols;
    final double tileH = (size.height - (rows - 1) * padding) / rows;

    // We use the smaller dimension to ensure squares if possible, 
    // or just fill the space.
    // Actually, "tiles" usually implies uniform shape. 
    // Let's try to make them roughly square-ish visually, but filling the allocated Size.
    
    final Paint paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < total; i++) {
      int row = i ~/ cols;
      int col = i % cols;

      double x = col * (tileW + padding);
      double y = row * (tileH + padding);

      // Determine color
      // Completed tiles
      if (i < current) {
         paint.color = color;
      } else {
         // Pending tiles
         paint.color = emptyColor.withValues(alpha: 0.3);
      }

      RRect rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, tileW, tileH),
        const Radius.circular(4), // Rounded corners for cuteness
      );
      
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return oldDelegate.current != current || 
           oldDelegate.total != total ||
           oldDelegate.aspectRatio != aspectRatio;
  }
}
