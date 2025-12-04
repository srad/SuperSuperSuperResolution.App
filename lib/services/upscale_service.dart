import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/upscale_config.dart';

class UpscaleResult {
  final Uint8List? imageBytes;
  final String? error;
  final int outputWidth;
  final int outputHeight;

  UpscaleResult({
    this.imageBytes,
    this.error,
    this.outputWidth = 0,
    this.outputHeight = 0,
  });

  bool get success => imageBytes != null && error == null;
}

class UpscaleProgress {
  final int current;
  final int total;
  final String message;

  UpscaleProgress({required this.current, required this.total, required this.message});

  double get fraction => total > 0 ? current / total : 0;
  String get percentText => '${(fraction * 100).toStringAsFixed(0)}%';
}

class UpscaleService {
  // Using the 50x50 fixed input model with tile-based processing
  static const String _modelAssetPath = 'assets/models/esrgan.tflite';
  static const MethodChannel _channel =
      MethodChannel('com.github.srad.magicresolution/litert');
  static const EventChannel _progressChannel =
      EventChannel('com.github.srad.magicresolution/progress');

  static bool _isInitialized = false;
  static bool _gpuAvailable = false;

  static Stream<UpscaleProgress>? _progressStream;

  /// Stream of progress updates during upscaling.
  static Stream<UpscaleProgress> get progressStream {
    _progressStream ??= _progressChannel.receiveBroadcastStream().map((event) {
      final map = event as Map;
      return UpscaleProgress(
        current: map['current'] as int,
        total: map['total'] as int,
        message: map['message'] as String,
      );
    });
    return _progressStream!;
  }

  /// Initialize LiteRT runtime (Android only).
  /// Call this once at app startup.
  static Future<bool> initialize() async {
    if (!Platform.isAndroid) {
      // Non-Android platforms not supported yet
      return false;
    }

    if (_isInitialized) return true;

    try {
      final result = await _channel.invokeMethod<Map>('initialize');
      _isInitialized = result?['success'] == true;
      _gpuAvailable = result?['gpuAvailable'] == true;
      debugPrint('LiteRT initialized: $_isInitialized, GPU available: $_gpuAvailable');
      return _isInitialized;
    } catch (e) {
      debugPrint('Failed to initialize LiteRT: $e');
      return false;
    }
  }

  /// Check if GPU acceleration is available on this device.
  static bool get isGpuAvailable => _gpuAvailable;

  /// Check if LiteRT is initialized.
  static bool get isInitialized => _isInitialized;

  /// Cancel any ongoing upscale operation.
  static Future<void> cancel() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('cancel');
    } catch (e) {
      debugPrint('Failed to cancel: $e');
    }
  }

  /// Upscales an image using ESRGAN model via LiteRT.
  ///
  /// [imageFile] - The input image file
  /// [config] - Configuration for delegate type, max size, threads
  /// [onProgress] - Optional callback for progress updates
  static Future<UpscaleResult> upscale(
    File imageFile,
    UpscaleConfig config, {
    void Function(String status)? onProgress,
  }) async {
    if (!Platform.isAndroid) {
      return UpscaleResult(error: 'Only Android is supported with LiteRT');
    }

    if (!_isInitialized) {
      onProgress?.call('Initializing LiteRT...');
      final success = await initialize();
      if (!success) {
        return UpscaleResult(error: 'Failed to initialize LiteRT');
      }
    }

    try {
      onProgress?.call('Loading model...');
      final modelData = await rootBundle.load(_modelAssetPath);
      final modelBytes = modelData.buffer.asUint8List();

      onProgress?.call('Reading image...');
      final imageBytes = await imageFile.readAsBytes();

      onProgress?.call('Upscaling with ${config.delegateType.name.toUpperCase()}...');

      final result = await _channel.invokeMethod<Map>('upscale', {
        'imageBytes': imageBytes,
        'modelBytes': modelBytes,
        'delegateType': config.delegateType == DelegateType.gpu ? 'GPU' : 'CPU',
        'maxInputDimension': config.maxInputDimension,
        'numThreads': config.numThreads,
      });

      if (result?['success'] == true) {
        return UpscaleResult(
          imageBytes: result!['imageBytes'] as Uint8List?,
          outputWidth: result['outputWidth'] as int? ?? 0,
          outputHeight: result['outputHeight'] as int? ?? 0,
        );
      } else {
        return UpscaleResult(error: result?['error'] as String? ?? 'Unknown error');
      }
    } catch (e) {
      return UpscaleResult(error: 'Upscale failed: $e');
    }
  }

  /// Upscale with automatic GPU fallback to CPU on failure.
  static Future<UpscaleResult> upscaleWithFallback(
    File imageFile,
    UpscaleConfig config, {
    void Function(String status)? onProgress,
  }) async {
    // Try with requested delegate first
    var result = await upscale(imageFile, config, onProgress: onProgress);

    // If GPU failed, retry with CPU
    if (!result.success && config.delegateType == DelegateType.gpu) {
      onProgress?.call('GPU failed, falling back to CPU...');
      result = await upscale(
        imageFile,
        config.copyWith(delegateType: DelegateType.cpu),
        onProgress: onProgress,
      );
    }

    return result;
  }
}
