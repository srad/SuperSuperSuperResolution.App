import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:magicresolution/models/upscale_config.dart';
import 'package:magicresolution/services/upscale_service.dart';
import 'package:magicresolution/utils/file_utils.dart';
import 'package:magicresolution/utils/image_utils.dart';
import 'package:magicresolution/widgets/comparison_slider.dart';
import 'package:magicresolution/widgets/tile_progress_indicator.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Magic Resolution',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF80AB), // Cute Pink
          secondary: const Color(0xFFB39DDB), // Soft Lavender
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFFFF0F5), // Lavender Blush
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Colors.black87,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            fontFamily: 'Rounded', // If available, else default looks ok
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: const Color(0xFFFF80AB),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 4,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF80AB),
            foregroundColor: Colors.white,
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // State
  File? _inputImage;
  SourceImageInfo? _imageInfo; // Added to track aspect ratio
  Uint8List? _outputImageBytes;
  int _outputWidth = 0;
  int _outputHeight = 0;
  bool _isProcessing = false;
  
  // Progress State
  String _progressMessage = '';
  String _statusMessage = '';
  double _progressValue = 0.0;
  int _totalTiles = 0; // Added for tile indicator
  int _currentTiles = 0; // Added for tile indicator
  
  // System State
  bool _isSystemReady = false;
  StreamSubscription<UpscaleProgress>? _progressSubscription;
  
  // Config
  bool _useGpu = true;
  
  // Use this flag to switch between progress indicators
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
        // Auto-detect best option but allow override
        if (UpscaleService.isGpuAvailable) {
          _useGpu = true;
        }
      });
      if (!success) {
         _showSnack('Failed to initialize AI engine 😢', isError: true);
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
        _outputImageBytes = null; // Reset output
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

  Future<void> _startProcessing() async {
    if (_inputImage == null) return;

    setState(() {
      _isProcessing = true;
      _progressValue = 0.0;
      _currentTiles = 0;
      _totalTiles = 0;
      _progressMessage = '0%';
      _statusMessage = 'Warming up engines... ✨';
    });

    // Subscribe to progress
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
      // Use fallback to ensure it works even if GPU fails
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
        setState(() {
          _outputImageBytes = result.imageBytes;
          _outputWidth = result.outputWidth;
          _outputHeight = result.outputHeight;
        });
      } else {
        _showSnack(result.error ?? 'Upscaling failed 😭', isError: true);
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
      final fileName = 'upscaled_cute_${DateTime.now().millisecondsSinceEpoch}.png';
      final outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Cute Image',
        fileName: fileName,
        type: FileType.image,
        allowedExtensions: ['png'],
        bytes: _outputImageBytes,
      );

      if (outputFile == null) return; // User canceled

      // Desktop needs manual write
      if (!Platform.isAndroid && !Platform.isIOS) {
         await File(outputFile).writeAsBytes(_outputImageBytes!);
      }

      _showSnack('Image saved! ✨');
    } catch (e) {
      _showSnack('Failed to save: $e', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFFB39DDB),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildInfoChip(String text, IconData icon, {bool isRight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // --- UI Components ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Magic Resolution ✨'),
        leading: _inputImage != null
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: _reset,
                tooltip: 'Close',
                color: const Color(0xFFFF80AB),
              )
            : null,
        actions: [
          if (_outputImageBytes == null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: Color(0xFFB39DDB)),
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
                    child: const Text('Turbo Mode (GPU) 🚀'),
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
            // Layer 1: Main Content
            Positioned.fill(
              child: _buildContent(),
            ),

            // Layer 2: Loading / Processing Overlay
            if (_isProcessing)
              Positioned.fill(
                child: _buildProcessingOverlay(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    // Case 1: Result (Before/After)
    if (_outputImageBytes != null && _inputImage != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ComparisonSlider(
            beforeImage: Image.file(
              _inputImage!,
              fit: BoxFit.contain,
            ),
            afterImage: Image.memory(
              _outputImageBytes!,
              fit: BoxFit.contain,
            ),
          ),
          
          // Output Resolution (Left)
          Positioned(
            bottom: 20,
            left: 20,
            child: _buildInfoChip(
              '${_outputWidth}x$_outputHeight',
              Icons.hd_rounded,
            ),
          ),

          // Input Resolution (Right)
          Positioned(
            bottom: 20,
            right: 20,
            child: _buildInfoChip(
              _imageInfo != null ? _imageInfo!.dimensionsString : 'Original',
              Icons.image_outlined,
              isRight: true,
            ),
          ),

          // Save Button
          Positioned(
            top: 16,
            right: 16,
            child: FloatingActionButton.extended(
              heroTag: 'save',
              onPressed: _saveImage,
              icon: const Icon(Icons.save_alt_rounded),
              label: const Text("Save Magic"),
            ),
          ),
        ],
      );
    }

    // Case 2: Image Selected (Ready to Enhance)
    if (_inputImage != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          // Preview
          Padding(
            padding: const EdgeInsets.only(bottom: 100.0), // Make room for button
            child: InteractiveViewer(
              child: Center(
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.file(_inputImage!),
                      ),
                    ),
                    // Info Overlay
                    if (_imageInfo != null)
                      Positioned(
                        bottom: 16,
                        left: 16,
                        child: _buildInfoChip(
                          '${_imageInfo!.dimensionsString} • ${_formatFileSize(_imageInfo!.fileSize)}',
                          Icons.info_outline_rounded,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          
          // Enhance Button (Floating at bottom)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Center(
                  child: FloatingActionButton.extended(
                    heroTag: 'enhance',
                    onPressed: _isSystemReady ? _startProcessing : null,
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: Text(
                      _isSystemReady ? "Make it Shiny! ✨" : "Warming up...",
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    backgroundColor: const Color(0xFFFF80AB),
                    elevation: 6,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Case 3: Empty State
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // The Cute Icon
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF80AB).withValues(alpha: 0.2),
                  blurRadius: 30,
                  spreadRadius: 5,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.all(24),
            child: ClipOval(
              child: Image.asset(
                'assets/icon.png',
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => Icon(
                  Icons.image_rounded,
                  size: 80,
                  color: const Color(0xFFFF80AB).withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
          const Text(
            "Let's Enhance!",
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: Colors.black87,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Pick a photo to add some magic ✨",
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 40),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
              textStyle: const TextStyle(fontSize: 18),
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFFFF80AB),
              elevation: 2,
              side: const BorderSide(color: Color(0xFFFF80AB), width: 2),
            ),
            onPressed: _pickImage,
            icon: const Icon(Icons.add_photo_alternate_rounded),
            label: const Text("Choose Photo"),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingOverlay() {
    return Stack(
      children: [
        // Blur
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
        
        // Content
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Switch between Tile and Circular progress
              if (_useTileProgress && _totalTiles > 0)
                TileProgressIndicator(
                  current: _currentTiles,
                  total: _totalTiles,
                  progressMessage: _progressMessage,
                  //statusMessage: _statusMessage,
                  aspectRatio: _imageInfo != null 
                    ? _imageInfo!.width / _imageInfo!.height 
                    : 1.0,
                )
              else
                // Fallback to old circular indicator
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 120,
                          height: 120,
                          child: CircularProgressIndicator(
                            value: _progressValue > 0 ? _progressValue : null,
                            strokeWidth: 8,
                            backgroundColor: const Color(0xFFFFE0EB),
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF80AB)),
                            strokeCap: StrokeCap.round,
                          ),
                        ),
                        Text(
                          _progressMessage,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFFF80AB),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    Text(
                      _statusMessage,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),

              const SizedBox(height: 60),
              
              // Warning/Cancel Button
              TextButton.icon(
                onPressed: _cancelProcessing,
                icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent),
                label: const Text(
                  "Cancel", 
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.redAccent),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
