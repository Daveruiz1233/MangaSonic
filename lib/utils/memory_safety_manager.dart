import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

/// Manages global memory safety, especially for low-RAM iOS devices.
class MemorySafetyManager with WidgetsBindingObserver {
  static final MemorySafetyManager _instance = MemorySafetyManager._internal();
  factory MemorySafetyManager() => _instance;
  MemorySafetyManager._internal();

  final _lowMemoryStreamController = StreamController<bool>.broadcast();
  Stream<bool> get lowMemoryStream => _lowMemoryStreamController.stream;

  bool _isUnderPressure = false;
  bool get isUnderPressure => _isUnderPressure;

  // Track active readers to avoid evicting live images while user is reading
  int _activeReaderCount = 0;
  int get activeReaderCount => _activeReaderCount;

  // Default limits (applied in _applyInitialLimits)
  int _defaultMaxBytes = 100 * 1024 * 1024;
  int _defaultMaxCount = 50;

  /// Initializes the manager and sets platform-specific image cache limits.
  void init() {
    WidgetsBinding.instance.addObserver(this);
    _applyInitialLimits();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lowMemoryStreamController.close();
  }

  void _applyInitialLimits() {
    if (Platform.isIOS) {
      // 100MB max for image cache on iOS (prevents OOM on iPhone 6s Plus)
      PaintingBinding.instance.imageCache.maximumSizeBytes = _defaultMaxBytes;
      PaintingBinding.instance.imageCache.maximumSize = _defaultMaxCount;
      debugPrint('MemorySafetyManager: Applied iOS image cache limits (100MB / 50 images)');
    }
  }

  @override
  void didHaveMemoryPressure() {
    debugPrint('MemorySafetyManager: SYSTEM MEMORY PRESSURE DETECTED');
    _isUnderPressure = true;
    // If there's an active reader open, avoid clearing live images immediately
    // to prevent visual glitches while scrolling. Instead, notify listeners
    // and reduce cache limits to discourage further decoding.
    if (_activeReaderCount > 0) {
      debugPrint('MemorySafetyManager: Reader active — deferring clearLiveImages()');
      // Reduce limits temporarily to prevent more allocations
      PaintingBinding.instance.imageCache.maximumSizeBytes = (_defaultMaxBytes / 2).toInt();
      final int reducedCount = (_defaultMaxCount ~/ 2).clamp(10, _defaultMaxCount);
      PaintingBinding.instance.imageCache.maximumSize = reducedCount;
    } else {
      // No reader visible — perform normal aggressive eviction
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    }

    // 2. Notify listeners (Reader) to shrink their windows
    _lowMemoryStreamController.add(true);
    
    // Reset pressure flag after a delay to allow window to expand again later if needed
    Timer(const Duration(minutes: 5), () {
      _isUnderPressure = false;
      _lowMemoryStreamController.add(false);
      // Restore default limits when pressure subsides (if no reader active)
      if (_activeReaderCount == 0) {
        PaintingBinding.instance.imageCache.maximumSizeBytes = _defaultMaxBytes;
        PaintingBinding.instance.imageCache.maximumSize = _defaultMaxCount;
      }
    });
  }

  /// Call when a reader screen becomes visible. While one or more readers are
  /// active we avoid clearing live images to prevent flicker.
  void registerReaderVisible() {
    _activeReaderCount++;
    if (_activeReaderCount == 1) {
      // When reader opens, increase cache allowance to reduce thrashing.
      PaintingBinding.instance.imageCache.maximumSizeBytes = (_defaultMaxBytes * 2);
      PaintingBinding.instance.imageCache.maximumSize = (_defaultMaxCount * 2);
      debugPrint('MemorySafetyManager: Reader registered — increased cache limits');
    }
  }

  /// Call when a reader screen is disposed/hidden.
  void unregisterReaderVisible() {
    if (_activeReaderCount > 0) _activeReaderCount--;
    if (_activeReaderCount == 0) {
      // Restore defaults
      PaintingBinding.instance.imageCache.maximumSizeBytes = _defaultMaxBytes;
      PaintingBinding.instance.imageCache.maximumSize = _defaultMaxCount;
      debugPrint('MemorySafetyManager: Reader unregistered — restored cache limits');

      // If we previously deferred eviction due to pressure, perform it now
      if (_isUnderPressure) {
        debugPrint('MemorySafetyManager: Performing deferred eviction now that reader closed');
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      }
    }
  }
}
