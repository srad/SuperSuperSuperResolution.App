import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img_lib;

class SourceImageInfo {
  final int width;
  final int height;
  final int fileSize;

  SourceImageInfo({required this.width, required this.height, required this.fileSize});

  bool exceedsMaxDimension(int maxDimension) =>
      width > maxDimension || height > maxDimension;

  String get dimensionsString => '${width}x$height';
}

class ImageUtils {
  static const int minDimension = 64;

  /// Gets basic info about an image file without fully decoding it.
  static Future<SourceImageInfo?> getImageInfo(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final image = img_lib.decodeImage(bytes);
      if (image == null) return null;

      return SourceImageInfo(
        width: image.width,
        height: image.height,
        fileSize: bytes.length,
      );
    } catch (e) {
      debugPrint('Failed to get image info: $e');
      return null;
    }
  }

  /// Resizes image to fit within maxDimension while maintaining aspect ratio.
  /// Returns null if the image is already within bounds.
  static img_lib.Image? resizeToFit(img_lib.Image image, int maxDimension) {
    if (image.width <= maxDimension && image.height <= maxDimension) {
      return null; // No resize needed
    }

    final scale = maxDimension / (image.width > image.height ? image.width : image.height);
    final newWidth = (image.width * scale).round();
    final newHeight = (image.height * scale).round();

    return img_lib.copyResize(
      image,
      width: newWidth,
      height: newHeight,
      interpolation: img_lib.Interpolation.cubic,
    );
  }

  /// Ensures image meets minimum dimensions (64x64 for ESRGAN).
  static img_lib.Image ensureMinimumSize(img_lib.Image image) {
    if (image.width >= minDimension && image.height >= minDimension) {
      return image;
    }

    int newWidth = image.width;
    int newHeight = image.height;

    if (newWidth < minDimension) {
      final scale = minDimension / newWidth;
      newWidth = minDimension;
      newHeight = (image.height * scale).round();
    }

    if (newHeight < minDimension) {
      final scale = minDimension / newHeight;
      newHeight = minDimension;
      newWidth = (image.width * scale).round();
    }

    return img_lib.copyResize(
      image,
      width: newWidth,
      height: newHeight,
      interpolation: img_lib.Interpolation.cubic,
    );
  }

  /// Preprocesses image: caps at maxDimension, ensures minimum 64x64.
  /// Returns the processed image and its dimensions.
  static Future<img_lib.Image> preprocessImage(
    File imageFile, {
    required int maxDimension,
  }) async {
    final bytes = await imageFile.readAsBytes();
    var image = img_lib.decodeImage(bytes);

    if (image == null) {
      throw Exception('Could not decode image');
    }

    // Cap at max dimension
    if (image.width > maxDimension || image.height > maxDimension) {
      image = resizeToFit(image, maxDimension) ?? image;
      debugPrint('Resized image to ${image.width}x${image.height}');
    }

    // Ensure minimum size
    image = ensureMinimumSize(image);

    return image;
  }

  /// Converts image to PNG bytes.
  static Uint8List encodeAsPng(img_lib.Image image) {
    return Uint8List.fromList(img_lib.encodePng(image));
  }

  /// Converts image to JPG bytes with quality setting.
  static Uint8List encodeAsJpg(img_lib.Image image, {int quality = 90}) {
    return Uint8List.fromList(img_lib.encodeJpg(image, quality: quality));
  }
}
