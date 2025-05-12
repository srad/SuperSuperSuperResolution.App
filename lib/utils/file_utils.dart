import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

class FileUtils {
  static Future<File?> pickImage(BuildContext context) async {
    final List<File>? files = await _picker(context, 1); // Expect a list
    if (files != null && files.isNotEmpty) {
      return files.first;
    }
    return null;
  }

  static Future<List<File>?> pickVideos(final BuildContext context, int limit) =>
      _picker(context, limit);

  static Future<List<File>?> _picker(BuildContext context, int maxNumber) async {
    try {
      final List<AssetEntity>? result = await AssetPicker.pickAssets(
        context,
        pickerConfig: AssetPickerConfig(
          maxAssets: maxNumber,
          requestType: RequestType.image,
        ),
      );

      if (result != null && result.isNotEmpty) {
        List<File> videoFiles = [];
        for (AssetEntity asset in result) {
          File? file = await asset.file; // Or .originFile
          if (file != null) {
            videoFiles.add(file);
          }
        }
        return videoFiles.isNotEmpty ? videoFiles : null; // Return the list or null if all conversions failed
      } else {
        debugPrint('User canceled video picking or no assets selected');
        return null; // Explicitly return null if result is null or empty
      }
    } catch (e) {
      debugPrint('Error picking videos with wechat_assets_picker: $e');
      return null; // Return null on error
    }
  }
}