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
      PaintingBinding.instance.imageCache.maximumSizeBytes = 100 * 1024 * 1024;
      PaintingBinding.instance.imageCache.maximumSize = 50;
      debugPrint('MemorySafetyManager: Applied iOS image cache limits (100MB / 50 images)');
    }
  }

  @override
  void didHaveMemoryPressure() {
    debugPrint('MemorySafetyManager: SYSTEM MEMORY PRESSURE DETECTED');
    _isUnderPressure = true;
    
    // 1. Clear the global image cache immediately
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    
    // 2. Notify listeners (Reader) to shrink their windows
    _lowMemoryStreamController.add(true);
    
    // Reset pressure flag after a delay to allow window to expand again later if needed
    Timer(const Duration(minutes: 5), () {
      _isUnderPressure = false;
      _lowMemoryStreamController.add(false);
    });
  }
}
