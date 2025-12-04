import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:magicresolution/models/upscale_config.dart';
import 'package:magicresolution/screens/views/image_preview_view.dart';
import 'package:magicresolution/screens/views/processing_overlay.dart';
import 'package:magicresolution/screens/views/result_view.dart';
import 'package:magicresolution/screens/views/start_view.dart';
import 'package:magicresolution/services/upscale_service.dart';
import 'package:magicresolution/theme/app_theme.dart';
import 'package:magicresolution/utils/file_utils.dart';
import 'package:magicresolution/utils/image_utils.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // State
  File? _inputImage;
  SourceImageInfo? _imageInfo;
  Uint8List? _outputImageBytes;
  int _outputWidth = 0;
  int _outputHeight = 0;
  bool _isProcessing = false;

  // Progress State
  String _progressMessage = '';
  String _statusMessage = '';
  double _progressValue = 0.0;
  int _totalTiles = 0;
  int _currentTiles = 0;

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
        });
      }
    });

    final config = UpscaleConfig(
      delegateType: _useGpu ? DelegateType.gpu : DelegateType.cpu,
      maxInputDimension: 1024,
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
        Uint8List finalBytes = result.imageBytes!;
        int finalWidth = result.outputWidth;
        int finalHeight = result.outputHeight;

        if (scaleFactor == 2) {
          setState(() => _statusMessage = 'Downsampling to 2x...');
          final downsampled = await _downsampleImage(
            result.imageBytes!,
            result.outputWidth ~/ 2,
            result.outputHeight ~/ 2,
          );
          finalBytes = downsampled.bytes;
          finalWidth = downsampled.width;
          finalHeight = downsampled.height;
        }

        setState(() {
          _outputImageBytes = finalBytes;
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
        });
      }
    }
  }

  Future<({Uint8List bytes, int width, int height})> _downsampleImage(
    Uint8List imageBytes,
    int targetWidth,
    int targetHeight,
  ) async {
    final image = img.decodeImage(imageBytes);
    if (image == null) {
      return (bytes: imageBytes, width: targetWidth * 2, height: targetHeight * 2);
    }

    final resized = img.copyResize(
      image,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.cubic,
    );

    final pngBytes = Uint8List.fromList(img.encodePng(resized));
    return (bytes: pngBytes, width: targetWidth, height: targetHeight);
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

    try {
      final fileName = 'upscaled_${DateTime.now().millisecondsSinceEpoch}.png';
      final outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Image',
        fileName: fileName,
        type: FileType.image,
        allowedExtensions: ['png'],
        bytes: _outputImageBytes,
      );

      if (outputFile == null) return;

      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(outputFile).writeAsBytes(_outputImageBytes!);
      }

      _showSnack('Image saved!');
    } catch (e) {
      _showSnack('Failed to save: $e', isError: true);
    }
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
      _inputImage = null;
      _imageInfo = null;
      _outputImageBytes = null;
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
          leading: _inputImage != null
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
                icon: const Icon(Icons.more_vert_rounded, color: AppTheme.secondaryLavender),
                tooltip: 'Settings',
                onSelected: (value) {
                  if (value == 'toggle_gpu') {
                    setState(() {
                      _useGpu = !_useGpu;
                    });
                  }
                },
                itemBuilder: (BuildContext context) {
                  return [
                    CheckedPopupMenuItem<String>(
                      value: 'toggle_gpu',
                      checked: _useGpu,
                      child: const Text('Turbo Mode (GPU)'),
                    ),
                  ];
                },
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
    if (_outputImageBytes != null && _inputImage != null) {
      return ResultView(
        inputImage: _inputImage!,
        imageInfo: _imageInfo,
        outputImageBytes: _outputImageBytes!,
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
}
