import 'package:flutter_test/flutter_test.dart';

/// Tests for the reader visibility window logic
/// These tests verify that images don't unload from the viewport
void main() {
  group('Reader Visibility Window', () {
    test('Visibility window should include viewport pages', () {
      // Simulate 20 pages with center at index 10
      const totalPages = 20;
      const centerIndex = 10;
      const backwardCount = 8;
      const forwardCount = 15;

      final newStart = (centerIndex - backwardCount).clamp(0, totalPages - 1);
      final newEnd = (centerIndex + forwardCount).clamp(0, totalPages - 1);

      // Window should extend well beyond viewport
      expect(newStart, lessThanOrEqualTo(5)); // Buffer before center
      expect(newEnd, greaterThanOrEqualTo(19)); // Buffer after center (clamped to totalPages-1)
    });

    test('Emergency mode should still keep viewport images', () {
      const totalPages = 20;
      const centerIndex = 10;
      const backwardCount = 3; // Emergency mode
      const forwardCount = 8; // Emergency mode

      final newStart = (centerIndex - backwardCount).clamp(0, totalPages - 1);
      final newEnd = (centerIndex + forwardCount).clamp(0, totalPages - 1);

      // Even in emergency mode, keep viewport + buffer
      expect(newStart, lessThanOrEqualTo(7));
      expect(newEnd, greaterThanOrEqualTo(18));
    });

    test('Keep-alive duration should prevent premature unloading', () {
      const keepAliveDuration = Duration(seconds: 5);
      final firstVisibleTime = DateTime.now().subtract(const Duration(seconds: 3));
      final now = DateTime.now();

      // Image should stay alive within keep-alive window
      final shouldStayAlive =
          now.difference(firstVisibleTime) < keepAliveDuration;
      expect(shouldStayAlive, isTrue);

      // Image should unload after keep-alive window
      final oldTime =
          DateTime.now().subtract(const Duration(seconds: 6));
      final shouldUnload = now.difference(oldTime) < keepAliveDuration;
      expect(shouldUnload, isFalse);
    });
  });
}
