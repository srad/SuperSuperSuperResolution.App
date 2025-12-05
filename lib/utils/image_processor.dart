import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Parameters for JPG encoding in isolate
class JpgEncodeParams {
  final Uint8List imageBytes;
  final int quality;

  JpgEncodeParams({required this.imageBytes, required this.quality});
}

/// Parameters for image resizing in isolate
class ResizeParams {
  final Uint8List imageBytes;
  final int targetWidth;
  final int targetHeight;

  ResizeParams({
    required this.imageBytes,
    required this.targetWidth,
    required this.targetHeight,
  });
}

/// Parameters for preview generation in isolate
class PreviewParams {
  final Uint8List imageBytes;
  final int width;
  final int height;
  final int maxDimension;

  PreviewParams({
    required this.imageBytes,
    required this.width,
    required this.height,
    required this.maxDimension,
  });
}

/// Result of a resize operation
class ResizeResult {
  final Uint8List bytes;
  final int width;
  final int height;

  ResizeResult({required this.bytes, required this.width, required this.height});
}

/// Image processing utilities that run in isolates to avoid UI freezing.
class ImageProcessor {
  static const int maxPreviewDimension = 1920;

  /// Encodes image to JPG with specified quality. Runs in isolate.
  static Future<Uint8List> encodeToJpg(Uint8List imageBytes, int quality) {
    return compute(_encodeToJpgIsolate, JpgEncodeParams(imageBytes: imageBytes, quality: quality));
  }

  /// Downsamples image to target dimensions. Runs in isolate.
  static Future<ResizeResult> downsample(Uint8List imageBytes, int targetWidth, int targetHeight) async {
    final result = await compute(
      _downsampleIsolate,
      ResizeParams(imageBytes: imageBytes, targetWidth: targetWidth, targetHeight: targetHeight),
    );
    return ResizeResult(
      bytes: result['bytes'] as Uint8List,
      width: result['width'] as int,
      height: result['height'] as int,
    );
  }

  /// Generates a display-sized preview image. Runs in isolate.
  /// Preview is capped at maxPreviewDimension (1920px) on the longest side.
  static Future<Uint8List> generatePreview(Uint8List imageBytes, int width, int height) {
    return compute(
      _generatePreviewIsolate,
      PreviewParams(
        imageBytes: imageBytes,
        width: width,
        height: height,
        maxDimension: maxPreviewDimension,
      ),
    );
  }
}

// Top-level isolate functions (must not be closures or instance methods)

Uint8List _encodeToJpgIsolate(JpgEncodeParams params) {
  final image = img.decodeImage(params.imageBytes);
  if (image == null) {
    throw Exception('Failed to decode image for JPG conversion');
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: params.quality));
}

Map<String, dynamic> _downsampleIsolate(ResizeParams params) {
  final image = img.decodeImage(params.imageBytes);
  if (image == null) {
    return {
      'bytes': params.imageBytes,
      'width': params.targetWidth * 2,
      'height': params.targetHeight * 2,
    };
  }

  final resized = img.copyResize(
    image,
    width: params.targetWidth,
    height: params.targetHeight,
    interpolation: img.Interpolation.cubic,
  );

  return {
    'bytes': Uint8List.fromList(img.encodePng(resized)),
    'width': params.targetWidth,
    'height': params.targetHeight,
  };
}

Uint8List _generatePreviewIsolate(PreviewParams params) {
  // If already within preview size, return as-is
  if (params.width <= params.maxDimension && params.height <= params.maxDimension) {
    return params.imageBytes;
  }

  final image = img.decodeImage(params.imageBytes);
  if (image == null) {
    throw Exception('Failed to decode image for preview');
  }

  // Calculate scaled dimensions maintaining aspect ratio
  final scale = params.maxDimension / (params.width > params.height ? params.width : params.height);
  final previewWidth = (params.width * scale).round();
  final previewHeight = (params.height * scale).round();

  final resized = img.copyResize(
    image,
    width: previewWidth,
    height: previewHeight,
    interpolation: img.Interpolation.cubic,
  );

  return Uint8List.fromList(img.encodePng(resized));
}
