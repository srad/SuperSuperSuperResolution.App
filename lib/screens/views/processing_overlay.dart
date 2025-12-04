import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:magicresolution/theme/app_theme.dart';
import 'package:magicresolution/widgets/tile_progress_indicator.dart';

class ProcessingOverlay extends StatelessWidget {
  final bool useTileProgress;
  final int totalTiles;
  final int currentTiles;
  final double progressValue;
  final String progressMessage;
  final String statusMessage;
  final double aspectRatio;
  final VoidCallback onCancel;

  const ProcessingOverlay({
    super.key,
    required this.useTileProgress,
    required this.totalTiles,
    required this.currentTiles,
    required this.progressValue,
    required this.progressMessage,
    required this.statusMessage,
    required this.aspectRatio,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Blur
        BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),

        // Content
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Switch between Tile and Circular progress
              if (useTileProgress && totalTiles > 0)
                TileProgressIndicator(
                  current: currentTiles,
                  total: totalTiles,
                  progressMessage: progressMessage,
                  aspectRatio: aspectRatio,
                )
              else
                _buildCircularProgress(),

              const SizedBox(height: 60),

              // Cancel Button
              TextButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent),
                label: const Text(
                  "Cancel",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCircularProgress() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 120,
              height: 120,
              child: CircularProgressIndicator(
                value: progressValue > 0 ? progressValue : null,
                strokeWidth: 8,
                backgroundColor: AppTheme.progressBackground,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryPink),
                strokeCap: StrokeCap.round,
              ),
            ),
            Text(
              progressMessage,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: AppTheme.primaryPink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 40),
        Text(
          statusMessage,
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
