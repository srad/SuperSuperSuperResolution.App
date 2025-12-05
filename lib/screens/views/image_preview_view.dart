import 'dart:io';

import 'package:flutter/material.dart';
import 'package:magicresolution/theme/app_theme.dart';
import 'package:magicresolution/utils/image_utils.dart';
import 'package:magicresolution/widgets/info_chip.dart';

class ImagePreviewView extends StatelessWidget {
  final File inputImage;
  final SourceImageInfo? imageInfo;
  final bool isSystemReady;
  final void Function(int scaleFactor) onStartProcessing;

  const ImagePreviewView({
    super.key,
    required this.inputImage,
    required this.imageInfo,
    required this.isSystemReady,
    required this.onStartProcessing,
  });

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Preview
        Padding(
          padding: const EdgeInsets.only(bottom: 100.0),
          child: InteractiveViewer(
            child: Center(
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.all(8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(inputImage),
                    ),
                  ),
                  // Info Overlay
                  if (imageInfo != null)
                    Positioned(
                      bottom: 16,
                      left: 16,
                      child: InfoChip(
                        text: '${imageInfo!.dimensionsString} - ${_formatFileSize(imageInfo!.fileSize)}',
                        icon: Icons.info_outline_rounded,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),

        // Enhance Buttons (Floating at bottom)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isSystemReady ? "Choose upscale factor" : "Warming up...",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 2x Button
                      FloatingActionButton.extended(
                        heroTag: 'enhance2x',
                        onPressed: isSystemReady ? () => onStartProcessing(2) : null,
                        icon: const Icon(Icons.auto_awesome_rounded),
                        label: const Text(
                          "2x",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        backgroundColor: AppTheme.secondaryLavender,
                        elevation: 4,
                      ),
                      const SizedBox(width: 16),
                      // 4x Button
                      FloatingActionButton.extended(
                        heroTag: 'enhance4x',
                        onPressed: isSystemReady ? () => onStartProcessing(4) : null,
                        icon: const Icon(Icons.auto_awesome_rounded),
                        label: const Text(
                          "4x",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        backgroundColor: AppTheme.primaryPink,
                        elevation: 6,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
