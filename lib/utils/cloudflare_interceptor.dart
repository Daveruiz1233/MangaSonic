import 'dart:async';
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

  static Future<void> bypass(String url) async {
    final completer = Completer<void>();
    HeadlessInAppWebView? headless;

    headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
      onLoadStop: (controller, uri) async {
        // Wait for cloudflare 5s challenge if needed
        await Future.delayed(const Duration(seconds: 5));

        final ua = await controller.evaluateJavascript(
          source: 'navigator.userAgent',
        );
        final currentCookies = await CookieManager.instance().getCookies(
          url: WebUri(url),
        );

        _userAgent = ua?.toString().replaceAll('"', '');
        _cookies = currentCookies.map((c) => '${c.name}=${c.value}').join('; ');
        _hasBypassed = true;

        completer.complete();
        headless?.dispose();
      },
    );

    await headless.run();
    return completer.future;
  }

  static bool get isReady => _hasBypassed;
}
