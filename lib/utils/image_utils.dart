import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img_lib;
import 'package:flutter/foundation.dart';

class ImageUtils {
  // --- Preprocessing ---
  // Converts the input image to the format expected by your ESRGAN model.
  // See details: https://www.kaggle.com/models/kaggle/esrgan-tf2/tfLite
  static Future<List<List<List<List<double>>>>> preprocessImage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    img_lib.Image? originalImage = img_lib.decodeImage(bytes);

    if (originalImage == null) {
      throw Exception('Could not decode image. The file might be corrupt or an unsupported format.');
    }

    // 1. Ensure image dimensions are >= 64x64.
    //    You can choose to resize to a fixed size (e.g., 64x64 if your model is optimized for that)
    //    or use the original dimensions if they are large enough and your model supports variable input sizes >= 64.
    //    For this example, let's ensure it's at least 64x64, but you might want a more sophisticated
    //    strategy, e.g. if the image is smaller than 64x64, upscale it first using a basic method,
    //    or inform the user. If it's much larger, you might offer to crop or resize.
    //    The description "Works best on Bicubically downsampled images" implies the input should
    //    ideally be a version of a larger image that was downsampled using bicubic interpolation.
    //    The `copyResize` method in the `image` package uses a good quality default.

    int targetWidth = originalImage.width;
    int targetHeight = originalImage.height;

    if (targetWidth < 64 || targetHeight < 64) {
      // Option 1: Resize to minimum 64x64 if smaller (maintaining aspect ratio)
      if (targetWidth < targetHeight) {
        targetHeight = (targetHeight * (64 / targetWidth)).round();
        targetWidth = 64;
      } else {
        targetWidth = (targetWidth * (64 / targetHeight)).round();
        targetHeight = 64;
      }
      // Or, you could simply reject images smaller than 64x64.
      // For now, let's just print a warning if we don't resize.
      debugPrint("Warning: Image dimensions are less than 64x64. Model performance might be affected.");
    }
    // For simplicity, if you want to resize to a fixed input size like 64x64:
    // img_lib.Image resizedImage = img_lib.copyResize(originalImage, width: 64, height: 64, interpolation: img_lib.Interpolation.cubic);
    // For this example, we'll use the original (or slightly adjusted if below 64) dimensions.
    // Ensure you know the exact input dimensions your TFLite model was converted with if it's not dynamic.
    // Let's assume for now the model can handle dynamic sizes >= 64x64.
    // If your model expects a FIXED input size (e.g. exactly 64x64), then you MUST resize:
    // img_lib.Image resizedImage = img_lib.copyResize(originalImage, width: 64, height: 64, interpolation: img_lib.Interpolation.cubic);
    // For this example, we'll use originalImage and assume its dimensions are >= 64.
    // YOU MUST ENSURE `originalImage` meets the model's specific input tensor dimensions.
    // Let's proceed assuming `originalImage` is appropriately sized (e.g., user selects a valid image or you've resized it).

    img_lib.Image inputImage = originalImage; // Use the (potentially resized) image

    // 2. Convert to a 4D float32 tensor [batch_size, height, width, 3]
    //    with pixel values in the range [0.0, 255.0].
    var imageAsList = List.generate(
      1, // Batch size (for a single image)
      (_) => List.generate(
        inputImage.height,
        (y) => List.generate(inputImage.width, (x) {
          final pixel = inputImage.getPixel(x, y);
          // The description `tf.cast(image, tf.float32)` implies direct conversion of uint8 pixel values to float32.
          return [
            pixel.r.toDouble(), // Red channel (0-255) as float32
            pixel.g.toDouble(), // Green channel (0-255) as float32
            pixel.b.toDouble(), // Blue channel (0-255) as float32
          ];
        }),
      ),
    );
    return imageAsList;
  }

  // --- Postprocessing ---
  // Converts the model's output tensor back into a displayable image.
  img_lib.Image? postprocessOutput(List<dynamic> outputTensorFromModel, List<int> modelOutputShape) {
    // Model output shape is typically [batch_size, height, width, channels]
    // For your x4 model, height and width will be 4 times the input image's height and width.
    // Channels should be 3 (R,G,B).

    if (outputTensorFromModel.isEmpty || outputTensorFromModel[0] == null) {
      debugPrint("Error: Output tensor is empty or invalid.");
      return null;
    }

    // Assuming batch_size is 1, get the first (and only) image's data.
    // The structure of outputTensorFromModel depends on how the TFLite plugin returns it.
    // It's often a List<List<List<List<double>>>> for a 4D tensor.
    var singleImageOutput = outputTensorFromModel[0] as List<List<List<double>>>;

    int outputHeight = modelOutputShape[1]; // e.g., inputHeight * 4
    int outputWidth = modelOutputShape[2]; // e.g., inputWidth * 4
    int channels = modelOutputShape[3];

    if (channels != 3) {
      debugPrint("Error: Expected 3 output channels (RGB), but got $channels.");
      return null;
    }

    var outputImage = img_lib.Image(width: outputWidth, height: outputHeight);

    for (int y = 0; y < outputHeight; y++) {
      for (int x = 0; x < outputWidth; x++) {
        // 3. Get pixel data (R,G,B) - these are float32 values
        double rFloat = singleImageOutput[y][x][0];
        double gFloat = singleImageOutput[y][x][1];
        double bFloat = singleImageOutput[y][x][2];

        // 4. Clip values to the range [0, 255] as per tf.clip_by_value(image, 0, 255)
        //    and then cast to uint8 (represented as int in Dart for image library).
        int rInt = rFloat.clamp(0.0, 255.0).toInt();
        int gInt = gFloat.clamp(0.0, 255.0).toInt();
        int bInt = bFloat.clamp(0.0, 255.0).toInt();

        outputImage.setPixelRgba(x, y, rInt, gInt, bInt, 255); // Alpha = 255 (opaque)
      }
    }
    return outputImage;
  }
}
