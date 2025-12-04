import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supersupersuperresolution/models/upscale_config.dart';
import 'package:supersupersuperresolution/services/upscale_service.dart';
import 'package:supersupersuperresolution/utils/file_utils.dart';
import 'package:supersupersuperresolution/utils/image_utils.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SuperSuperSuperResolution AI Upscaler',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigoAccent),
      ),
      home: const MyHomePage(title: 'SSSR AI Upscaler'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  Uint8List? _processedImageBytes;
  bool _isLoading = false;
  bool _isInitializing = true;
  String _statusMessage = '';
  File? _selectedImage;
  SourceImageInfo? _selectedImageInfo;

  // Progress tracking
  StreamSubscription<UpscaleProgress>? _progressSubscription;
  UpscaleProgress? _currentProgress;

  // Configuration state
  DelegateType _delegateType = DelegateType.gpu;
  static const int _maxInputDimension = 1024;

  UpscaleConfig get _config => UpscaleConfig(
        delegateType: _delegateType,
        maxInputDimension: _maxInputDimension,
      );

  @override
  void initState() {
    super.initState();
    _initializeLiteRT();
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeLiteRT() async {
    setState(() => _isInitializing = true);

    final success = await UpscaleService.initialize();

    setState(() {
      _isInitializing = false;
      if (success) {
        _statusMessage = 'Ready${UpscaleService.isGpuAvailable ? ' (GPU available)' : ''}';
      } else {
        _statusMessage = 'Failed to initialize LiteRT';
      }
    });
  }

  Future<void> pickImage() async {
    final image = await FileUtils.pickImage(context);

    if (image != null) {
      final file = File(image.path);
      final info = await ImageUtils.getImageInfo(file);

      setState(() {
        _selectedImage = file;
        _selectedImageInfo = info;
        _processedImageBytes = null;
      });
    }
  }

  Future<void> _processImage() async {
    if (_selectedImage == null) return;

    setState(() {
      _isLoading = true;
      _processedImageBytes = null;
      _statusMessage = 'Starting...';
      _currentProgress = null;
    });

    // Listen to progress updates
    _progressSubscription?.cancel();
    _progressSubscription = UpscaleService.progressStream.listen((progress) {
      setState(() {
        _currentProgress = progress;
        _statusMessage = progress.message;
      });
    });

    try {
      final result = await UpscaleService.upscaleWithFallback(
        _selectedImage!,
        _config,
        onProgress: (status) {
          setState(() => _statusMessage = status);
        },
      );

      if (result.success) {
        setState(() {
          _processedImageBytes = result.imageBytes;
          _statusMessage = 'Done! Output: ${result.outputWidth}x${result.outputHeight}';
          _currentProgress = null;
        });
      } else {
        _showError(result.error ?? 'Unknown error');
      }
    } catch (e) {
      _showError('Processing failed: $e');
    } finally {
      _progressSubscription?.cancel();
      setState(() {
        _isLoading = false;
        _currentProgress = null;
      });
    }
  }

  void _showError(String message) {
    setState(() => _statusMessage = message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _toggleDelegate() {
    setState(() {
      _delegateType = _delegateType == DelegateType.cpu
          ? DelegateType.gpu
          : DelegateType.cpu;
    });
  }

  String get _delegateLabel =>
      _delegateType == DelegateType.cpu ? 'CPU' : 'GPU';

  Future<void> _saveWithDialog() async {
    if (_processedImageBytes == null) return;

    try {
      final outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save upscaled image',
        fileName: 'upscaled_${DateTime.now().millisecondsSinceEpoch}.png',
        type: FileType.image,
        allowedExtensions: ['png'],
        bytes: _processedImageBytes,
      );

      if (outputFile == null) {
        // User canceled the picker
        return;
      }

      // On Android, bytes are written automatically when provided
      // On desktop, we need to write manually
      if (!Platform.isAndroid && !Platform.isIOS) {
        final file = File(outputFile);
        await file.writeAsBytes(_processedImageBytes!);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to: $outputFile')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          TextButton.icon(
            onPressed: _isLoading || _isInitializing ? null : _toggleDelegate,
            icon: Icon(
              _delegateType == DelegateType.gpu ? Icons.memory : Icons.computer,
              color: Colors.black87,
            ),
            label: Text(
              _delegateLabel,
              style: const TextStyle(color: Colors.black87),
            ),
          ),
        ],
      ),
      body: _isInitializing
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Initializing LiteRT...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Input image section
                  if (_selectedImage != null) ...[
                    Card(
                      child: Column(
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Text('Input',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          Image.file(
                            _selectedImage!,
                            height: 200,
                            fit: BoxFit.contain,
                          ),
                          if (_selectedImageInfo != null)
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                '${_selectedImageInfo!.dimensionsString} • ${(_selectedImageInfo!.fileSize / 1024).toStringAsFixed(1)} KB'
                                '${_selectedImageInfo!.exceedsMaxDimension(_maxInputDimension) ? ' (input will be resized to max $_maxInputDimension)' : ''}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : pickImage,
                          icon: const Icon(Icons.image),
                          label: const Text('Pick Image'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed:
                              _isLoading || _selectedImage == null ? null : _processImage,
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('Enhance'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Progress indicator
                  if (_isLoading) ...[
                    if (_currentProgress != null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: LinearProgressIndicator(
                              value: _currentProgress!.fraction,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _currentProgress!.percentText,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_currentProgress!.message} (${_currentProgress!.current}/${_currentProgress!.total})',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ] else ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                      Text(
                        _statusMessage,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],

                  // Status message when not loading
                  if (!_isLoading && _statusMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        _statusMessage,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),

                  // Output image section
                  if (_processedImageBytes != null) ...[
                    Card(
                      child: Column(
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Text('Output (4x)',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          Image.memory(
                            _processedImageBytes!,
                            fit: BoxFit.contain,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _saveWithDialog,
                      icon: const Icon(Icons.save),
                      label: const Text('Save As...'),
                    ),
                  ],

                  // Info card
                  const SizedBox(height: 24),
                  Card(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Settings',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '• Max input: ${_maxInputDimension}x$_maxInputDimension\n'
                            '• Output: 4x upscaled (tile-based)\n'
                            '• Delegate: $_delegateLabel${UpscaleService.isGpuAvailable ? '' : ' (GPU not available)'}\n'
                            '• Threads: ${_config.numThreads}/${UpscaleConfig.availableProcessors}\n'
                            '• Runtime: LiteRT (Google Play Services)\n'
                            '• Model: ESRGAN (50x50 tiles)',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
