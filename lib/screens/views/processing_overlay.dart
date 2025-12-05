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
  final bool isGpuMode;
  final bool isPostProcessing;
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
    required this.isGpuMode,
    required this.isPostProcessing,
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
              // Mode Indicator (hide during post-processing)
              if (!isPostProcessing)
                Container(
                  margin: const EdgeInsets.only(bottom: 32),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isGpuMode
                        ? AppTheme.secondaryLavender.withValues(alpha: 0.2)
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isGpuMode ? AppTheme.secondaryLavender : Colors.grey.shade400,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isGpuMode ? Icons.bolt_rounded : Icons.speed_rounded,
                        size: 18,
                        color: isGpuMode ? AppTheme.primaryPink : Colors.grey.shade700,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isGpuMode ? "Accelerated Mode (GPU)" : "Standard Mode (CPU)",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isGpuMode ? AppTheme.primaryPink : Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),

              // Switch between Post-processing, Tile, and Circular progress
              if (isPostProcessing)
                _buildPostProcessingIndicator()
              else if (useTileProgress && totalTiles > 0)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5,
                  ),
                  child: TileProgressIndicator(
                    current: currentTiles,
                    total: totalTiles,
                    progressMessage: progressMessage,
                    aspectRatio: aspectRatio,
                  ),
                )
              else
                _buildCircularProgress(),

              const SizedBox(height: 40),

              // Cancel Button (only show during upscaling, not post-processing)
              if (!isPostProcessing)
                ElevatedButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text(
                    "Cancel",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPostProcessingIndicator() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Animated spinner
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.primaryPink.withValues(alpha: 0.1),
          ),
          child: Center(
            child: SizedBox(
              width: 60,
              height: 60,
              child: CircularProgressIndicator(
                strokeWidth: 5,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryPink),
                strokeCap: StrokeCap.round,
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        // Status message
        Text(
          statusMessage,
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
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
