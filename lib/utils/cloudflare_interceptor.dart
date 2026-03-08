import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class CloudflareInterceptor {
  static String? _userAgent;
  static String? _cookies;
  static bool _hasBypassed = false;

  static Map<String, String> get headers {
    final Map<String, String> h = {
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
    };
    if (_userAgent != null) h['User-Agent'] = _userAgent!;
    if (_cookies != null) h['Cookie'] = _cookies!;
    return h;
  }

  static Completer<void>? _currentBypassCompleter;

  static Future<void> bypass(String url) async {
    // If already bypassing, just wait for that one.
    if (_currentBypassCompleter != null && !_currentBypassCompleter!.isCompleted) {
      debugPrint('CloudflareInterceptor: Already bypassing, waiting for current... ($url)');
      return _currentBypassCompleter!.future;
    }

    _currentBypassCompleter = Completer<void>();
    HeadlessInAppWebView? headless;

    debugPrint('CloudflareInterceptor: Starting bypass for $url');

    Timer? safetyTimer;

    void cleanup() {
      safetyTimer?.cancel();
      if (!(_currentBypassCompleter?.isCompleted ?? true)) {
        _currentBypassCompleter?.complete();
      }
      headless?.dispose();
      headless = null;
    }

    headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
      onLoadStop: (controller, uri) async {
        debugPrint('CloudflareInterceptor: Page load finished, waiting for challenge... ($uri)');
        
        // Wait for cloudflare 5s challenge
        await Future.delayed(const Duration(seconds: 6));

        try {
          if (headless == null) return; // Already cleaned up

          final ua = await controller.evaluateJavascript(
            source: 'navigator.userAgent',
          );
          final currentCookies = await CookieManager.instance().getCookies(
            url: WebUri(url),
          );

          _userAgent = ua?.toString().replaceAll('"', '');
          _cookies = currentCookies.map((c) => '${c.name}=${c.value}').join('; ');
          _hasBypassed = true;
          debugPrint('CloudflareInterceptor: Bypass data extracted successfully');
        } catch (e) {
          debugPrint('CloudflareInterceptor: Extraction failed: $e');
        } finally {
          cleanup();
        }
      },
      onLoadError: (controller, url, code, message) {
        debugPrint('CloudflareInterceptor: Load error ($code): $message');
        cleanup();
      },
      onReceivedHttpError: (controller, request, errorResponse) {
        debugPrint('CloudflareInterceptor: HTTP error (${errorResponse.statusCode}): ${errorResponse.reasonPhrase}');
        // Don't cleanup on 403 here, we expect the challenge page
      },
    );

    // Safety timeout: 25 seconds for the WHOLE process
    safetyTimer = Timer(const Duration(seconds: 25), () {
      debugPrint('CloudflareInterceptor: GLOBABL BYPASS TIMEOUT (25s)');
      cleanup();
    });

    try {
      await headless!.run();
      debugPrint('CloudflareInterceptor: Headless instance running...');
    } catch (e) {
      debugPrint('CloudflareInterceptor: Failed to start headless: $e');
      cleanup();
    }

    return _currentBypassCompleter!.future;
  }

  static bool get isReady => _hasBypassed;
}
