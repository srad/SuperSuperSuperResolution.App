import 'dart:io';

/// Hardware acceleration delegate types for TFLite inference.
///
/// Note: NNAPI was deprecated in Android 15 and removed.
/// See: https://developer.android.com/ndk/guides/neuralnetworks/migration-guide
enum DelegateType {
  /// CPU with XNNPack optimization (multi-threaded, most stable)
  cpu,

  /// GPU delegate (faster but may crash on some devices/models)
  gpu,
}

class UpscaleConfig {
  final DelegateType delegateType;
  final int maxInputDimension;
  final int? _numThreads;

  const UpscaleConfig({
    this.delegateType = DelegateType.cpu,
    this.maxInputDimension = 1024,
    int? numThreads,
  }) : _numThreads = numThreads;

  /// Returns configured threads or half of available processors (min 1).
  int get numThreads {
    if (_numThreads != null) return _numThreads;
    final available = Platform.numberOfProcessors;
    return (available / 2).ceil().clamp(1, available);
  }

  /// Available processors on this device.
  static int get availableProcessors => Platform.numberOfProcessors;

  UpscaleConfig copyWith({
    DelegateType? delegateType,
    int? maxInputDimension,
    int? numThreads,
  }) {
    return UpscaleConfig(
      delegateType: delegateType ?? this.delegateType,
      maxInputDimension: maxInputDimension ?? this.maxInputDimension,
      numThreads: numThreads ?? _numThreads,
    );
  }

  @override
  String toString() =>
      'UpscaleConfig(delegate: $delegateType, maxInput: $maxInputDimension, threads: $numThreads/$availableProcessors)';
}
