import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:manga_sonic/data/models/custom_source_model.dart';
import 'package:manga_sonic/utils/cloudflare_interceptor.dart';

/// Result of auto-detecting a site's template/CMS type.
class DetectionResult {
  final TemplateType templateType;
  final double confidence;
  final Map<String, String> extractedSelectors;
  final List<SampleManga> sampleManga;
  final String? rawHtml;

  DetectionResult({
    required this.templateType,
    required this.confidence,
    required this.extractedSelectors,
    this.sampleManga = const [],
    this.rawHtml,
  });
}

class SampleManga {
  final String title;
  final String url;
  final String coverUrl;

  SampleManga({
    required this.title,
    required this.url,
    required this.coverUrl,
  });
}

/// Auto-detection engine that identifies which CMS/template a manga
/// website uses, then returns pre-configured selectors.
class SiteTemplateDetector {
  final http.Client _client = http.Client();

  Future<http.Response> _get(String url) async {
    debugPrint('SiteTemplateDetector: Fetching $url');
    return http.get(
      Uri.parse(url),
      headers: {
        ...CloudflareInterceptor.headers,
      },
    ).timeout(const Duration(seconds: 15));
  }

  /// Detect the template for a given base URL.
  Future<DetectionResult> detect(String baseUrl, {bool isRetry = false}) async {
    final normalizedUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';

    http.Response response;
    try {
      response = await _get(normalizedUrl);

      // Layer 1: Cloudflare Bypass
      if (response.statusCode == 403 || response.statusCode == 429) {
        if (!isRetry) {
          debugPrint(
              'SiteTemplateDetector: Cloudflare block (${response.statusCode}). Attempting bypass...');
          await CloudflareInterceptor.bypass(normalizedUrl);
          return await detect(baseUrl, isRetry: true);
        } else {
          throw Exception('Cloudflare bypass failed for $baseUrl after retry');
        }
      }
    } catch (e) {
      if (e.toString().contains('Cloudflare block detected')) {
        if (!isRetry) {
          debugPrint(
              'SiteTemplateDetector: Interceptor threw block. Attempting bypass...');
          await CloudflareInterceptor.bypass(normalizedUrl);
          return await detect(baseUrl, isRetry: true);
        } else {
          throw Exception('Cloudflare bypass failed for $baseUrl');
        }
      }
      rethrow;
    }

    final rawHtml = response.body;
    final document = html_parser.parse(rawHtml);
    final bodyText = document.body?.outerHtml ?? '';

    // --- Priority 1: Madara (WordPress manga theme) ---
    if (_isMadara(bodyText)) {
      final selectors = _madaraSelectors(normalizedUrl);
      final samples = _extractMadaraSamples(document, normalizedUrl);
      return DetectionResult(
        templateType: TemplateType.madara,
        confidence: samples.isNotEmpty ? 0.95 : 0.75,
        extractedSelectors: selectors,
        sampleManga: samples,
        rawHtml: rawHtml,
      );
    }

    // --- Priority 2: MangaStream (ts_reader) ---
    if (_isMangaStream(bodyText)) {
      final selectors = _mangaStreamSelectors(normalizedUrl);
      final samples = _extractMangaStreamSamples(document, normalizedUrl);
      return DetectionResult(
        templateType: TemplateType.mangastream,
        confidence: samples.isNotEmpty ? 0.95 : 0.75,
        extractedSelectors: selectors,
        sampleManga: samples,
        rawHtml: rawHtml,
      );
    }

    // --- Priority 3: MangaReader PHP ---
    if (_isMangaReaderPhp(bodyText)) {
      final selectors = _mangaReaderSelectors(normalizedUrl);
      final samples = _extractMangaReaderSamples(document, normalizedUrl);
      return DetectionResult(
        templateType: TemplateType.mangareader,
        confidence: samples.isNotEmpty ? 0.90 : 0.70,
        extractedSelectors: selectors,
        sampleManga: samples,
        rawHtml: rawHtml,
      );
    }

    // --- Priority 4: RSC / React (Next.js) ---
    if (_isRsc(bodyText)) {
      final selectors = _rscSelectors(normalizedUrl);
      final samples = _extractRscSamples(document, normalizedUrl);
      return DetectionResult(
        templateType: TemplateType.rsc,
        confidence: samples.isNotEmpty ? 0.85 : 0.60,
        extractedSelectors: selectors,
        sampleManga: samples,
        rawHtml: rawHtml,
      );
    }

    // --- URL-based Fallback (Low confidence) ---
    final host = Uri.parse(normalizedUrl).host.toLowerCase();
    if (host.contains('asura') || host.contains('reaper') || host.contains('flame') || host.contains('realm')) {
      return DetectionResult(
        templateType: TemplateType.rsc,
        confidence: 0.7,
        extractedSelectors: _rscSelectors(normalizedUrl),
        sampleManga: [],
        rawHtml: rawHtml,
      );
    }
    if (host.contains('tx') || host.contains('top') || host.contains('kiss') || host.contains('scan')) {
      return DetectionResult(
        templateType: TemplateType.madara,
        confidence: 0.5,
        extractedSelectors: _madaraSelectors(normalizedUrl),
        sampleManga: [],
        rawHtml: rawHtml,
      );
    }
    if (host.contains('kakalot') || host.contains('nato') || host.contains('nelo')) {
      return DetectionResult(
         templateType: TemplateType.generic, // Will use heuristics but URL hints help confidence
         confidence: 0.8,
         extractedSelectors: _madaraSelectors(normalizedUrl), // They often mimic Madara structure
         sampleManga: [],
         rawHtml: rawHtml,
      );
    }

    // --- Fallback: Unknown → AI needed ---
    return DetectionResult(
      templateType: TemplateType.generic,
      confidence: 0.0,
      extractedSelectors: {},
      sampleManga: [],
      rawHtml: rawHtml,
    );
  }

  // ── Detection heuristics ──────────────────────────────────

  bool _isMadara(String html) {
    return html.contains('.wp-manga-chapter') ||
        html.contains('manga_get_chapters') ||
        html.contains('/wp-content/') ||
        html.contains('wp-manga') ||
        html.contains('madara');
  }

  bool _isMangaReaderPhp(String html) {
    return html.contains('#nt_listchapter') ||
        html.contains('.page-chapter') ||
        html.contains('/all-manga/');
  }

  bool _isMangaStream(String html) {
    return html.contains('ts_reader.run') ||
        html.contains('.bsx') ||
        html.contains('.bixbox') ||
        html.contains('.eplister') ||
        html.contains('series/') && html.contains('genre/');
  }

  bool _isRsc(String html) {
    return html.contains('__next') ||
        html.contains('__NEXT_DATA__') ||
        html.contains('_buildManifest') ||
        html.contains('react') && html.contains('hydrat') ||
        html.contains('reaper-') ||
        html.contains('flame-') ||
        html.contains('series-list') ||
        html.contains('grid-cols-');
  }

  // ── Preset selector bundles ───────────────────────────────

  static Map<String, String> _madaraSelectors(String baseUrl) {
    return {
      'listUrl': '${baseUrl}manga/page/{page}/',
      'searchUrl': '$baseUrl?s={query}&post_type=wp-manga',
      'mangaList': '.page-item-detail, .c-tabs-item__content, .item, .manga, .book-item',
      'mangaLink': 'a',
      'mangaImage': 'img',
      'chapterList': '.wp-manga-chapter a, ul.main li.wp-manga-chapter a',
      'chapterLink': 'a',
      'chapterImages': '.page-break img, .reading-content img',
      'description': '.description-summary, .summary__content p',
      'author': '.author-content a',
      'status': '.post-status .summary-content',
      'genres': '.genres-content a',
    };
  }

  static Map<String, String> _mangaReaderSelectors(String baseUrl) {
    return {
      'listUrl': '${baseUrl}all-manga/{page}/',
      'searchUrl': '${baseUrl}search?keyword={query}&page={page}',
      'mangaList': '.item',
      'mangaLink': '.jtip',
      'mangaImage': 'img',
      'chapterList': '#nt_listchapter .chapter a',
      'chapterLink': 'a',
      'chapterImages': '.page-chapter img',
      'description': '.detail-content p',
      'author': '.list-info li', // Will be refined in parser if needed
      'status': '.list-info li',
      'genres': '.list-info a',
    };
  }

  static Map<String, String> _mangaStreamSelectors(String baseUrl) {
    return {
      'listUrl': '${baseUrl}manga/?page={page}&order=update',
      'searchUrl': '${baseUrl}?s={query}',
      'mangaList': '.bsx, .listupd .item',
      'mangaLink': 'a',
      'mangaImage': 'img',
      'chapterList': '.eplister li a, #chapterlist li a',
      'chapterLink': 'a',
      'chapterImages': '__ts_reader__',
      'description': '.entry-content p, .seriestext',
      'author': '.infotable tr, .fmed span',
      'status': '.infotable tr, .fmed span',
      'genres': '.mgen a',
    };
  }

  static Map<String, String> _rscSelectors(String baseUrl) {
    return {
      'listUrl': '${baseUrl}series?page={page}',
      'searchUrl': '${baseUrl}series?name={query}&page={page}',
      'mangaList': 'div[class*="grid-cols"], div[class*="MuiGrid-"], .manga-card, .list-item',
      'mangaLink': 'a[href*="series/"], a[href*="manga/"]',
      'mangaImage': 'img',
      'chapterList': 'a[href*="/chapter/"], a[href*="/read/"]',
      'chapterLink': 'a',
      'chapterImages': '__script_regex__',
      'imageUrlPattern':
          r'https?://[^\s"]+(?:/storage/media/\d+/|/images/chapters/)[^\s"]+',
      'description': 'span[class*="text-"], .description, .summary',
      'author': '',
      'status': '',
      'genres': 'button[class*="bg-"], .genres a',
    };
  }

  /// Get the preset selectors for a given template type.
  static Map<String, String> presetSelectors(
      TemplateType type, String baseUrl) {
    switch (type) {
      case TemplateType.madara:
        return _madaraSelectors(baseUrl);
      case TemplateType.mangareader:
        return _mangaReaderSelectors(baseUrl);
      case TemplateType.mangastream:
        return _mangaStreamSelectors(baseUrl);
      case TemplateType.rsc:
        return _rscSelectors(baseUrl);
      default:
        return {};
    }
  }

  // ── Sample extraction ─────────────────────────────────────

  List<SampleManga> _extractMadaraSamples(dynamic document, String baseUrl) {
    final elements = document.querySelectorAll(
        '.page-item-detail, .c-tabs-item__content, .item');
    final List<SampleManga> samples = [];
    for (var element in elements) {
      final aTag = element.querySelector('a');
      final imgTag = element.querySelector('img');
      if (aTag != null && imgTag != null) {
        final url = aTag.attributes['href'] ?? '';
        final title =
            aTag.attributes['title'] ?? imgTag.attributes['alt'] ?? '';
        final coverUrl =
            imgTag.attributes['src'] ?? imgTag.attributes['data-src'] ?? '';
        if (url.isNotEmpty && title.isNotEmpty) {
          samples.add(SampleManga(
            title: title.trim(),
            url: _resolveUrl(url, baseUrl),
            coverUrl: coverUrl,
          ));
        }
      }
      if (samples.length >= 6) break;
    }
    return samples;
  }

  List<SampleManga> _extractMangaReaderSamples(
      dynamic document, String baseUrl) {
    final elements = document.querySelectorAll('.item');
    final List<SampleManga> samples = [];
    for (var element in elements) {
      final aTag = element.querySelector('.jtip') ?? element.querySelector('a');
      final imgTag = element.querySelector('img');
      if (aTag != null && imgTag != null) {
        var url = aTag.attributes['href'] ?? '';
        if (url.startsWith('/')) url = '${baseUrl.replaceAll(RegExp(r'/$'), '')}$url';
        final title = aTag.text.trim();
        final coverUrl = imgTag.attributes['data-original'] ??
            imgTag.attributes['data-src'] ??
            imgTag.attributes['src'] ??
            '';
        if (url.isNotEmpty && title.isNotEmpty) {
          samples.add(SampleManga(
            title: title,
            url: url,
            coverUrl: coverUrl,
          ));
        }
      }
      if (samples.length >= 6) break;
    }
    return samples;
  }

  List<SampleManga> _extractMangaStreamSamples(
      dynamic document, String baseUrl) {
    final elements = document.querySelectorAll('.bsx, .listupd .item');
    final List<SampleManga> samples = [];
    for (var element in elements) {
      final aTag = element.querySelector('a');
      final imgTag = element.querySelector('img');
      if (aTag != null && imgTag != null) {
        final url = aTag.attributes['href'] ?? '';
        final title = aTag.attributes['title'] ?? imgTag.attributes['alt'] ?? '';
        final coverUrl = imgTag.attributes['src'] ??
            imgTag.attributes['data-lazy-src'] ??
            imgTag.attributes['data-src'] ??
            '';
        if (url.isNotEmpty && title.isNotEmpty) {
          samples.add(SampleManga(
            title: title.trim(),
            url: _resolveUrl(url, baseUrl),
            coverUrl: coverUrl,
          ));
        }
      }
      if (samples.length >= 6) break;
    }
    return samples;
  }

  List<SampleManga> _extractRscSamples(dynamic document, String baseUrl) {
    // Look for grid containers with manga links
    final links = document.querySelectorAll('a[href*="series/"]');
    final List<SampleManga> samples = [];
    final Set<String> seen = {};

    for (var aTag in links) {
      final href = aTag.attributes['href'] ?? '';
      if (href.isEmpty) continue;
      final url = Uri.parse(baseUrl).resolve(href).toString();
      if (seen.contains(url)) continue;
      seen.add(url);

      // Try to find a title
      String title = '';
      final spans = aTag.querySelectorAll('span');
      for (var s in spans) {
        final cl = s.className.toString();
        if (cl.contains('font-bold') || cl.contains('font-[600]')) {
          title = s.text.trim();
          break;
        }
      }
      if (title.isEmpty) continue;

      final img = aTag.querySelector('img');
      final coverUrl =
          img?.attributes['src'] ?? img?.attributes['data-src'] ?? '';

      samples.add(SampleManga(
        title: title,
        url: url,
        coverUrl: coverUrl,
      ));
      if (samples.length >= 6) break;
    }
    return samples;
  }

  String _resolveUrl(String url, String baseUrl) {
    if (url.startsWith('http')) return url;
    if (url.startsWith('/')) {
      final uri = Uri.parse(baseUrl);
      return '${uri.scheme}://${uri.host}$url';
    }
    return '$baseUrl$url';
  }

  void dispose() {
    _client.close();
  }
}
