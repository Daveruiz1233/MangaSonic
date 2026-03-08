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
    return await _client.get(
      Uri.parse(url),
      headers: {...CloudflareInterceptor.headers},
    );
  }

  /// Detect the template for a given base URL.
  Future<DetectionResult> detect(String baseUrl) async {
    final normalizedUrl =
        baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';

    final response = await _get(normalizedUrl);
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

    // --- Priority 2: MangaReader PHP ---
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

    // --- Priority 3: RSC / React (Next.js) ---
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
        html.contains('/all-manga/') ||
        html.contains('nt_listchapter');
  }

  bool _isRsc(String html) {
    return html.contains('__next') ||
        html.contains('__NEXT_DATA__') ||
        html.contains('_buildManifest') ||
        html.contains('react') && html.contains('hydrat');
  }

  // ── Preset selector bundles ───────────────────────────────

  static Map<String, String> _madaraSelectors(String baseUrl) {
    return {
      'listUrl': '${baseUrl}manga/page/{page}/',
      'searchUrl': '$baseUrl?s={query}&post_type=wp-manga',
      'mangaList': '.page-item-detail, .c-tabs-item__content, .item',
      'mangaLink': 'a',
      'mangaImage': 'img',
      'chapterList': '.wp-manga-chapter a',
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
      'author': '.list-info li:has(.col-xs-4:contains("Author")) .col-xs-8',
      'status': '.list-info li:has(.col-xs-4:contains("Status")) .col-xs-8',
      'genres': '.list-info li:has(.col-xs-4:contains("Genres")) .col-xs-8 a',
    };
  }

  static Map<String, String> _rscSelectors(String baseUrl) {
    return {
      'listUrl': '${baseUrl}series?page={page}',
      'searchUrl': '${baseUrl}series?name={query}&page={page}',
      'mangaList': 'div[class*="grid-cols"]',
      'mangaLink': 'a[href*="series/"]',
      'mangaImage': 'img',
      'chapterList': 'a[href*="/chapter/"]',
      'chapterLink': 'a',
      'chapterImages': '__script_regex__',
      'imageUrlPattern':
          r'https?://[^\s"]+/storage/media/\d+/conversions/\d+-optimized\.webp',
      'description': 'span[class*="text-"]',
      'author': '',
      'status': '',
      'genres': 'button[class*="bg-"]',
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
