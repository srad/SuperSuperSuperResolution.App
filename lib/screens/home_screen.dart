import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:magicresolution/models/upscale_config.dart';
import 'package:magicresolution/screens/views/image_preview_view.dart';
import 'package:magicresolution/screens/views/processing_overlay.dart';
import 'package:magicresolution/screens/views/result_view.dart';
import 'package:magicresolution/screens/views/start_view.dart';
import 'package:magicresolution/services/upscale_service.dart';
import 'package:magicresolution/theme/app_theme.dart';
import 'package:magicresolution/utils/file_utils.dart';
import 'package:magicresolution/utils/image_processor.dart';
import 'package:magicresolution/utils/image_utils.dart';
import 'package:magicresolution/widgets/save_options_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // State
  File? _inputImage;
  SourceImageInfo? _imageInfo;
  Uint8List? _outputImageBytes; // Full resolution for saving
  Uint8List? _previewImageBytes; // Display resolution for preview
  int _outputWidth = 0;
  int _outputHeight = 0;
  bool _isProcessing = false;

  // Progress State
  String _progressMessage = '';
  String _statusMessage = '';
  double _progressValue = 0.0;
  int _totalTiles = 0;
  int _currentTiles = 0;
  bool _isPostProcessing = false; // True when upscaling done, preparing result

  // System State
  bool _isSystemReady = false;
  StreamSubscription<UpscaleProgress>? _progressSubscription;

  // Config
  bool _useGpu = true;
  final bool _useTileProgress = true;

  @override
  void initState() {
    super.initState();
    _initSystem();
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initSystem() async {
    final success = await UpscaleService.initialize();
    if (mounted) {
      setState(() {
        _isSystemReady = success;
        if (UpscaleService.isGpuAvailable) {
          _useGpu = true;
        }
      });
      if (!success) {
        _showSnack('Failed to initialize AI engine', isError: true);
      }
    }
  }

  // --- Actions ---

  Future<void> _pickImage() async {
    final image = await FileUtils.pickImage(context);
    if (image != null) {
      final file = File(image.path);
      final info = await ImageUtils.getImageInfo(file);

      setState(() {
        _inputImage = file;
        _imageInfo = info;
        _outputImageBytes = null;
      });
    }
  }

  void _reset() {
    setState(() {
      _inputImage = null;
      _imageInfo = null;
      _outputImageBytes = null;
      _previewImageBytes = null;
    });
  }

  Future<void> _startProcessing(int scaleFactor) async {
    if (_inputImage == null) return;

    setState(() {
      _isProcessing = true;
      _progressValue = 0.0;
      _currentTiles = 0;
      _totalTiles = 0;
      _progressMessage = '0%';
      _statusMessage = 'Warming up engines...';
    });

    _progressSubscription?.cancel();
    _progressSubscription = UpscaleService.progressStream.listen((progress) {
      if (mounted) {
        setState(() {
          _progressValue = progress.fraction;
          _currentTiles = progress.current;
          _totalTiles = progress.total;
          _progressMessage = '${(progress.fraction * 100).toInt()}%';
          _statusMessage = progress.message;

          // Switch to post-processing UI as soon as we hit 100%
          // (native code is still saving the file, but tiles are done)
          if (progress.fraction >= 1.0 && !_isPostProcessing) {
            _isPostProcessing = true;
            _statusMessage = 'Saving image...';
          }
        });
      }
    });

    final config = UpscaleConfig(
      delegateType: _useGpu ? DelegateType.gpu : DelegateType.cpu,
      maxInputDimension: 2048,
    );

    try {
      final result = await UpscaleService.upscaleWithFallback(
        _inputImage!,
        config,
        onProgress: (status) {
          if (mounted) {
            setState(() => _statusMessage = status);
          }
        },
      );

      if (!mounted) return;

      if (result.success) {
        // Switch to post-processing mode (show different UI)
        setState(() {
          _isPostProcessing = true;
          _statusMessage = 'Reading result...';
        });

        // Allow UI to update before heavy work
        await Future.delayed(const Duration(milliseconds: 50));

        // Read bytes from temp file (avoids OOM during MethodChannel transfer)
        final imageBytes = await result.readImageBytes();
        if (imageBytes == null) {
          _showSnack('Failed to read upscaled image', isError: true);
          return;
        }

        Uint8List finalBytes = imageBytes;
        int finalWidth = result.outputWidth;
        int finalHeight = result.outputHeight;

        if (scaleFactor == 2) {
          setState(() => _statusMessage = 'Downsampling to 2x...');
          await Future.delayed(const Duration(milliseconds: 50)); // Allow UI update
          final downsampled = await ImageProcessor.downsample(
            imageBytes,
            result.outputWidth ~/ 2,
            result.outputHeight ~/ 2,
          );
          finalBytes = downsampled.bytes;
          finalWidth = downsampled.width;
          finalHeight = downsampled.height;
        }

        // Generate preview image for display (max display resolution)
        setState(() => _statusMessage = 'Preparing preview...');
        await Future.delayed(const Duration(milliseconds: 50)); // Allow UI update
        Uint8List previewBytes;
        try {
          previewBytes = await ImageProcessor.generatePreview(finalBytes, finalWidth, finalHeight);
        } catch (e) {
          debugPrint('Preview generation failed: $e');
          _showSnack('Failed to generate preview: $e', isError: true);
          await result.cleanup(); // Clean up temp file
          return;
        }

        // Clean up temp file after we've read the bytes
        await result.cleanup();

        setState(() {
          _outputImageBytes = finalBytes;
          _previewImageBytes = previewBytes;
          _outputWidth = finalWidth;
          _outputHeight = finalHeight;
        });
      } else {
        _showSnack(result.error ?? 'Upscaling failed', isError: true);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Error: $e', isError: true);
      }
    } finally {
      _progressSubscription?.cancel();
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _isPostProcessing = false;
        });
      }
    }
  }

  void _cancelProcessing() {
    UpscaleService.cancel();
    _progressSubscription?.cancel();
    setState(() {
      _isProcessing = false;
    });
    _showSnack('Processing canceled');
  }

  Future<void> _saveImage() async {
    if (_outputImageBytes == null) return;

    // Show save options dialog
    final saveOptions = await _showSaveOptionsDialog();
    if (saveOptions == null) return; // User cancelled

    // Show loading dialog
    _showSavingDialog();

    try {
      // Encode image in chosen format (run in isolate to avoid UI freeze)
      final Uint8List outputBytes;
      final String extension;

      if (saveOptions.format == ImageFormat.png) {
        outputBytes = _outputImageBytes!; // Already PNG
        extension = 'png';
      } else {
        // Convert to JPG with quality setting in a separate isolate
        outputBytes = await ImageProcessor.encodeToJpg(_outputImageBytes!, saveOptions.quality);
        extension = 'jpg';
      }

      // Dismiss loading dialog before showing file picker
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      final fileName = 'upscaled_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Image',
        fileName: fileName,
        type: FileType.image,
        allowedExtensions: [extension],
        bytes: outputBytes,
      );

      if (outputFile == null) return;

      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(outputFile).writeAsBytes(outputBytes);
      }

      _showSnack('Image saved as ${extension.toUpperCase()}!');
    } catch (e) {
      // Dismiss loading dialog on error
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      _showSnack('Failed to save: $e', isError: true);
    }
  }

  void _showSavingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 20),
                Text('Preparing image...', style: TextStyle(fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<SaveOptions?> _showSaveOptionsDialog() async {
    return showDialog<SaveOptions>(
      context: context,
      builder: (context) => const SaveOptionsDialog(),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: isError ? Colors.redAccent : AppTheme.secondaryLavender,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _handleBack() async {
    // Block back navigation during post-processing (can't cancel at this stage)
    if (_isPostProcessing) {
      return;
    }

    // If processing, cancel and go to start
    if (_isProcessing) {
      _cancelAndReset();
      return;
    }

    // If we have output, show confirmation dialog
    if (_outputImageBytes != null) {
      final shouldDiscard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Discard Image?'),
          content: const Text(
            'You have an unsaved upscaled image. Are you sure you want to discard it?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              child: const Text('Discard'),
            ),
          ],
        ),
      );

      if (shouldDiscard == true) {
        _reset();
      }
    } else {
      _reset();
    }
  }

  void _cancelAndReset() {
    UpscaleService.cancel();
    _progressSubscription?.cancel();
    _progressSubscription = null;
    setState(() {
      _isProcessing = false;
      _isPostProcessing = false;
      _inputImage = null;
      _imageInfo = null;
      _outputImageBytes = null;
      _previewImageBytes = null;
      _progressValue = 0.0;
      _currentTiles = 0;
      _totalTiles = 0;
      _progressMessage = '';
      _statusMessage = '';
    });
  }

  // --- UI ---

  bool get _shouldInterceptBack =>
      _isProcessing || _outputImageBytes != null || _inputImage != null;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_shouldInterceptBack,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Magic Resolution'),
          leading: _inputImage != null && !_isPostProcessing
              ? IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _handleBack,
                  tooltip: 'Close',
            color: AppTheme.primaryPink,
          )
              : null,
          actions: [
            if (_outputImageBytes == null)
              PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded,
                      color: AppTheme.secondaryLavender),
                  tooltip: 'Settings',
                  onSelected: (value) => _handleMenuAction(context, value),
                  itemBuilder: (BuildContext context) =>
                  [
                    CheckedPopupMenuItem<String>(
                      value: 'toggle_gpu',
                      checked: _useGpu,
                      child: const Text('Accelerated Mode (GPU)'),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'rate',
                      child: Row(
                        children: [
                          Icon(
                            Icons.star_rate_rounded,
                            color: Theme
                                .of(context)
                                .iconTheme
                                .color,
                          ),
                          const SizedBox(width: 12),
                          const Text('Rate this app'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'instagram',
                      child: Row(
                        children: [
                          Icon(
                            Icons.photo_camera,
                            color: Theme
                                .of(context)
                                .iconTheme
                                .color,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          const Text('Instagram'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'more_apps',
                      child: Row(
                        children: [
                          Icon(Icons.apps, color: Theme
                              .of(context)
                              .iconTheme
                              .color),
                          const SizedBox(width: 12),
                          const Text('More of my Apps'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'about',
                      child: Row(
                        children: [
                          Icon(Icons.info, color: Theme
                              .of(context)
                              .iconTheme
                              .color),
                          const SizedBox(width: 12),
                          const Text('About'),
                        ],
                      ),
                    ),
                  ]
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Stack(
            children: [
              Positioned.fill(
                child: _buildContent(),
              ),
              if (_isProcessing)
                Positioned.fill(
                  child: ProcessingOverlay(
                    useTileProgress: _useTileProgress,
                    totalTiles: _totalTiles,
                    currentTiles: _currentTiles,
                    progressValue: _progressValue,
                    progressMessage: _progressMessage,
                    statusMessage: _statusMessage,
                    aspectRatio: _imageInfo != null
                        ? _imageInfo!.width / _imageInfo!.height
                        : 1.0,
                    isGpuMode: _useGpu,
                    isPostProcessing: _isPostProcessing,
                    onCancel: _cancelProcessing,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    // Case 1: Result (Before/After)
    if (_outputImageBytes != null && _previewImageBytes != null && _inputImage != null) {
      return ResultView(
        inputImage: _inputImage!,
        imageInfo: _imageInfo,
        previewImageBytes: _previewImageBytes!,
        outputWidth: _outputWidth,
        outputHeight: _outputHeight,
        onSave: _saveImage,
      );
    }

    // Case 2: Image Selected (Ready to Enhance)
    if (_inputImage != null) {
      return ImagePreviewView(
        inputImage: _inputImage!,
        imageInfo: _imageInfo,
        isSystemReady: _isSystemReady,
        onStartProcessing: _startProcessing,
      );
    }

    // Case 3: Empty State
    return StartView(onPickImage: _pickImage);
  }

  Future<void> _handleMenuAction(BuildContext context, String action) async {
    switch (action) {
      case 'toggle_gpu':
        setState(() {
          _useGpu = !_useGpu;
        });
        break;
      case 'about':
        final packageInfo = await PackageInfo.fromPlatform();
        if (context.mounted) {
          _showAboutDialog(context, packageInfo.version);
        }
        break;
      case 'rate':
        final InAppReview inAppReview = InAppReview.instance;
        // Replace with your actual App Store ID and Microsoft Store ID
        inAppReview.openStoreListing(
          appStoreId: 'YOUR_APP_STORE_ID',
          microsoftStoreId: 'YOUR_MICROSOFT_STORE_ID',
        );
        break;
      case 'instagram':
        _launchUrl('https://www.instagram.com/sedrad_com/');
        break;
      case 'more_apps':
        _launchUrl(
          'https://play.google.com/store/apps/developer?id=sedrad.com',
        );
        break;
      case 'reset':
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('All adjustments reset')));
        break;
    }
  }

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not launch $urlString')));
      }
    }
  }

  void _showAboutDialog(BuildContext context, String version) async {
    if (!mounted) return;

    final packageInfo = await PackageInfo.fromPlatform();

    showAboutDialog(
      context: context,
      applicationName: packageInfo.appName,
      applicationVersion: "$version+${packageInfo.buildNumber}",
      applicationLegalese: '© 2025 ${packageInfo.appName}',
      applicationIcon: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          image: const DecorationImage(
            image: AssetImage('assets/icon.png'),
            fit: BoxFit.cover,
          ),
        ),
      ),
      children: [
        const SizedBox(height: 24),
        const Text('Developer', style: TextStyle(fontWeight: FontWeight.bold)),
        const Text('Saman Sedighi Rad'),
        const SizedBox(height: 16),
        const Text('Website', style: TextStyle(fontWeight: FontWeight.bold)),
        InkWell(
          onTap: () => _launchUrl('https://sedrad.com'),
          child: Text(
            'https://sedrad.com',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Instagram', style: TextStyle(fontWeight: FontWeight.bold)),
        InkWell(
          onTap: () => _launchUrl('https://www.instagram.com/sedrad_com/'),
          child: Text(
            '@sedrad_com',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Google Play Store',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        InkWell(
          onTap: () => _launchUrl(
            'https://play.google.com/store/apps/developer?id=sedrad.com',
          ),
          child: Text(
            'More Apps on the Play Store',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Rate App', style: TextStyle(fontWeight: FontWeight.bold)),
        InkWell(
          onTap: () => _launchUrl(
            'https://play.google.com/store/apps/details?id=com.github.srad.magicresolution&showAllReviews=true',
          ),
          child: Text(
            'Rate on Play Store',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }
}
