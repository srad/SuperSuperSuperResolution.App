import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:magicresolution/utils/image_utils.dart';
import 'package:magicresolution/widgets/comparison_slider.dart';
import 'package:magicresolution/widgets/info_chip.dart';

class ResultView extends StatelessWidget {
  final File inputImage;
  final SourceImageInfo? imageInfo;
  final Uint8List outputImageBytes;
  final int outputWidth;
  final int outputHeight;
  final VoidCallback onSave;

  const ResultView({
    super.key,
    required this.inputImage,
    required this.imageInfo,
    required this.outputImageBytes,
    required this.outputWidth,
    required this.outputHeight,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ComparisonSlider(
          beforeImage: Image.file(
            inputImage,
            fit: BoxFit.contain,
          ),
          afterImage: Image.memory(
            outputImageBytes,
            fit: BoxFit.contain,
          ),
        ),

        // Output Resolution (Left)
        Positioned(
          bottom: 20,
          left: 20,
          child: InfoChip(
            text: '${outputWidth}x$outputHeight',
            icon: Icons.hd_rounded,
          ),
        ),

        // Input Resolution (Right)
        Positioned(
          bottom: 20,
          right: 20,
          child: InfoChip(
            text: imageInfo != null ? imageInfo!.dimensionsString : 'Original',
            icon: Icons.image_outlined,
          ),
        ),

        // Save Button
        Positioned(
          top: 16,
          right: 16,
          child: FloatingActionButton.extended(
            heroTag: 'save',
            onPressed: onSave,
            icon: const Icon(Icons.save_alt_rounded),
            label: const Text("Save"),
          ),
        ),
      ],
    );
  }
}
