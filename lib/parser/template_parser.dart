import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:manga_sonic/data/models/custom_source_model.dart';
import 'package:manga_sonic/data/models/models.dart';
import 'base_parser.dart';

/// A configurable parser driven by CSS selectors from a [CustomSourceModel].
/// Supports Madara, MangaReader-PHP, RSC, AI-generated, and generic templates.
class TemplateParser extends BaseParser {
  final CustomSourceModel source;

  TemplateParser(this.source)
      : super(siteName: source.name, baseUrl: source.url);

  Map<String, String> get sel => source.selectors;

  // ── Helpers ────────────────────────────────────────────────

  String _buildUrl(String template, {int page = 1, String query = ''}) {
    return template
        .replaceAll('{page}', page.toString())
        .replaceAll('{query}', Uri.encodeQueryComponent(query));
  }

  String _resolveUrl(String url) {
    if (url.startsWith('http')) return url;
    if (url.startsWith('/')) {
      final uri = Uri.parse(baseUrl);
      return '${uri.scheme}://${uri.host}$url';
    }
    return '$baseUrl$url';
  }

  String _imageAttr(dynamic imgTag) {
    if (imgTag == null) return '';
    return (imgTag.attributes['data-src'] ??
            imgTag.attributes['data-original'] ??
            imgTag.attributes['src'] ??
            '')
        .toString()
        .trim();
  }

  // ── fetchMangaList ────────────────────────────────────────

  @override
  Future<List<Manga>> fetchMangaList(int page) async {
    final listUrl = sel['listUrl'];
    if (listUrl == null || listUrl.isEmpty) {
      // Fallback: just fetch the base URL
      return _parseMangaPage(baseUrl);
    }
    final url = _buildUrl(listUrl, page: page);
    return _parseMangaPage(url);
  }

  Future<List<Manga>> _parseMangaPage(String url) async {
    final response = await getRequest(url);
    final document = html_parser.parse(response.body);

    // RSC grid-based detection
    if (source.templateType == TemplateType.rsc) {
      return _parseRscMangaList(document);
    }

    final mangaListSelector = sel['mangaList'] ?? '.item';
    final mangaLinkSelector = sel['mangaLink'] ?? 'a';
    final mangaImageSelector = sel['mangaImage'] ?? 'img';

    final elements = document.querySelectorAll(mangaListSelector);
    final List<Manga> list = [];

    for (var element in elements) {
      final aTag = element.querySelector(mangaLinkSelector);
      final imgTag = element.querySelector(mangaImageSelector);
      if (aTag == null) continue;

      final href = aTag.attributes['href'] ?? '';
      if (href.isEmpty) continue;
      final mangaUrl = _resolveUrl(href);

      final title = (aTag.attributes['title'] ??
              imgTag?.attributes['alt'] ??
              aTag.text.trim())
          .toString()
          .trim();
      if (title.isEmpty) continue;

      final coverUrl = _imageAttr(imgTag);

      list.add(Manga(
        title: title,
        url: mangaUrl,
        coverUrl: coverUrl,
        sourceId: source.sourceId,
      ));
    }
    return list;
  }

  List<Manga> _parseRscMangaList(dynamic document) {
    final linkSelector = sel['mangaLink'] ?? 'a[href*="series/"]';
    final links = document.querySelectorAll(linkSelector);
    final List<Manga> list = [];
    final Set<String> seen = {};

    for (var aTag in links) {
      final href = aTag.attributes['href'] ?? '';
      if (href.isEmpty) continue;
      final url = Uri.parse(baseUrl).resolve(href).toString();
      if (seen.contains(url)) continue;
      seen.add(url);

      String title = '';
      final spans = aTag.querySelectorAll('span');
      for (var s in spans) {
        final cl = s.className.toString();
        if (cl.contains('font-bold') || cl.contains('font-[600]')) {
          title = s.text.trim();
          break;
        }
      }
      if (title.isEmpty) {
        title = aTag.text.trim().split('\n').first.trim();
      }
      if (title.isEmpty) continue;

      final img = aTag.querySelector('img');
      final coverUrl = _imageAttr(img);

      list.add(Manga(
        title: title,
        url: url,
        coverUrl: coverUrl,
        sourceId: source.sourceId,
      ));
    }
    return list;
  }

  // ── searchManga ───────────────────────────────────────────

  @override
  Future<List<Manga>> searchManga(String query, int page) async {
    final searchUrl = sel['searchUrl'];
    if (searchUrl == null || searchUrl.isEmpty) return [];
    final url = _buildUrl(searchUrl, query: query, page: page);
    return _parseMangaPage(url);
  }

  // ── fetchMangaDetails ─────────────────────────────────────

  @override
  Future<MangaDetails> fetchMangaDetails(Manga manga) async {
    final response = await getRequest(manga.url);
    final document = html_parser.parse(response.body);

    String description = '';
    final descSel = sel['description'] ?? '';
    if (descSel.isNotEmpty) {
      // Try each selector separated by comma
      for (final s in descSel.split(',')) {
        final el = document.querySelector(s.trim());
        if (el != null && el.text.trim().length > 10) {
          description = el.text.trim();
          break;
        }
      }
    }

    String author = 'Unknown';
    final authorSel = sel['author'] ?? '';
    if (authorSel.isNotEmpty) {
      final el = document.querySelector(authorSel);
      if (el != null) author = el.text.trim();
    }

    String status = 'Unknown';
    final statusSel = sel['status'] ?? '';
    if (statusSel.isNotEmpty) {
      final el = document.querySelector(statusSel);
      if (el != null) status = el.text.trim();
    }

    List<String> genres = [];
    final genresSel = sel['genres'] ?? '';
    if (genresSel.isNotEmpty) {
      final els = document.querySelectorAll(genresSel);
      genres = els.map((e) => e.text.trim()).toList();
    }

    final chapters = await fetchChapters(manga.url);

    return MangaDetails(
      description: description.isEmpty
          ? 'Description not available for this source.'
          : description,
      author: author.isEmpty ? 'Unknown' : author,
      artist: 'Unknown',
      status: status.isEmpty ? 'Unknown' : status,
      genres: genres,
      chapters: chapters,
      suggestions: [],
    );
  }

  // ── fetchChapters ─────────────────────────────────────────

  @override
  Future<List<Chapter>> fetchChapters(String mangaUrl) async {
    // Madara template: use the 3-tier fallback strategy
    if (source.templateType == TemplateType.madara) {
      return _fetchMadaraChapters(mangaUrl);
    }

    final response = await getRequest(mangaUrl);
    final document = html_parser.parse(response.body);
    return _extractChapters(document, mangaUrl);
  }

  Future<List<Chapter>> _fetchMadaraChapters(String mangaUrl) async {
    var response = await getRequest(mangaUrl);
    var document = html_parser.parse(response.body);

    final chapterSelector = sel['chapterList'] ?? '.wp-manga-chapter a';
    var chapterElements = document.querySelectorAll(chapterSelector);

    // Tier 2: ajax/chapters/ POST
    if (chapterElements.isEmpty) {
      final ajaxUrl = mangaUrl.endsWith('/')
          ? '${mangaUrl}ajax/chapters/'
          : '$mangaUrl/ajax/chapters/';
      try {
        response = await postRequest(
          ajaxUrl,
          headers: {'X-Requested-With': 'XMLHttpRequest'},
        );
        if (response.statusCode == 200) {
          document = html_parser.parse(response.body);
          chapterElements = document.querySelectorAll(chapterSelector);
        }
      } catch (e) {
        debugPrint('TemplateParser: ajax/chapters/ failed: $e');
      }
    }

    // Tier 3: admin-ajax.php POST
    if (chapterElements.isEmpty) {
      final idTag = document.querySelector('#manga-chapters-holder');
      final mangaId = idTag?.attributes['data-id'];
      if (mangaId != null) {
        final baseUri = Uri.parse(baseUrl);
        response = await postRequest(
          '${baseUri.scheme}://${baseUri.host}/wp-admin/admin-ajax.php',
          body: {'action': 'manga_get_chapters', 'manga': mangaId},
          headers: {'X-Requested-With': 'XMLHttpRequest'},
        );
        document = html_parser.parse(response.body);
        chapterElements = document.querySelectorAll(chapterSelector);
      }
    }

    final List<Chapter> chapters = [];
    for (var element in chapterElements) {
      final url = element.attributes['href'] ?? '';
      final title = element.text.trim();
      String? releaseDate;
      final parent = element.parent?.parent;
      if (parent != null) {
        final dateEl = parent.querySelector(
            '.chapter-release-date, .post-on');
        releaseDate = dateEl?.text.trim();
      }
      if (url.isNotEmpty) {
        chapters.add(Chapter(
          title: title,
          url: _resolveUrl(url),
          mangaUrl: mangaUrl,
          releaseDate: releaseDate,
        ));
      }
    }
    return chapters;
  }

  List<Chapter> _extractChapters(dynamic document, String mangaUrl) {
    final chapterSelector = sel['chapterList'] ?? 'a';

    // RSC template: chapter links matching /chapter/
    if (source.templateType == TemplateType.rsc) {
      return _extractRscChapters(document, mangaUrl);
    }

    final elements = document.querySelectorAll(chapterSelector);
    final List<Chapter> chapters = [];

    for (var element in elements) {
      var url = element.attributes['href'] ?? '';
      if (url.isEmpty) continue;
      url = _resolveUrl(url);

      final title = element.text.trim();
      String? releaseDate;
      final parent = element.parent?.parent;
      if (parent != null) {
        final dateEl =
            parent.querySelector('.post-on, .chapter-release-date');
        releaseDate = dateEl?.text.trim();
      }

      if (title.isNotEmpty) {
        chapters.add(Chapter(
          title: title,
          url: url,
          mangaUrl: mangaUrl,
          releaseDate: releaseDate,
        ));
      }
    }
    return chapters;
  }

  List<Chapter> _extractRscChapters(dynamic document, String mangaUrl) {
    final chapterElements =
        document.querySelectorAll('a[href*="/chapter/"]');
    final List<Chapter> chapters = [];
    final baseUri = Uri.parse(mangaUrl);

    for (var element in chapterElements) {
      final href = element.attributes['href'] ?? '';
      if (href.isEmpty) continue;
      final url = baseUri.resolve(href).toString();
      if (!url.contains('/chapter/')) continue;

      final h3s = element.querySelectorAll('h3');
      String chapterName = '';
      String? releaseDate;

      if (h3s.isNotEmpty) {
        chapterName = h3s.first.text.trim();
        if (h3s.length > 1) {
          releaseDate = h3s[1].text.trim();
        }
      } else {
        chapterName =
            element.text.trim().replaceAll(RegExp(r'\s+'), ' ').trim();
      }

      if (chapterName == 'First Chapter' ||
          chapterName == 'New Chapter' ||
          chapterName.isEmpty) {
        continue;
      }

      if (!chapters.any((c) => c.url == url)) {
        chapters.add(Chapter(
          title: chapterName,
          url: url,
          mangaUrl: mangaUrl,
          releaseDate: releaseDate,
        ));
      }
    }
    return chapters;
  }

  // ── fetchChapterImages ────────────────────────────────────

  @override
  Future<List<String>> fetchChapterImages(String chapterUrl) async {
    final response = await getRequest(chapterUrl);
    final document = html_parser.parse(response.body);

    final imagesSelector = sel['chapterImages'] ?? '';

    // RSC/React: regex-based extraction from <script> tags
    if (imagesSelector == '__script_regex__' ||
        source.templateType == TemplateType.rsc) {
      return _extractRscImages(document);
    }

    // Standard CSS selector-based extraction
    if (imagesSelector.isNotEmpty) {
      final images = document.querySelectorAll(imagesSelector);
      final List<String> list = [];
      for (var img in images) {
        final src = _imageAttr(img);
        if (src.isNotEmpty) {
          list.add(_resolveUrl(src));
        }
      }
      return list;
    }

    // Generic fallback: all images in the page body
    final images = document.querySelectorAll('img');
    final List<String> list = [];
    for (var img in images) {
      final src = _imageAttr(img);
      if (src.isNotEmpty && _looksLikeMangaImage(src)) {
        list.add(_resolveUrl(src));
      }
    }
    return list;
  }

  List<String> _extractRscImages(dynamic document) {
    final patternStr = sel['imageUrlPattern'] ??
        r'https?://[^\s"]+/storage/media/\d+/conversions/\d+-optimized\.webp';
    final pattern = RegExp(patternStr);

    final Set<String> seen = {};
    final List<_NumberedImage> pages = [];

    final scripts = document.querySelectorAll('script');
    for (var script in scripts) {
      final text = script.text;
      for (var match in pattern.allMatches(text)) {
        final url = match.group(0)!;
        // Try to extract a page number from the URL
        final numMatch = RegExp(r'/(\d+)-').firstMatch(url);
        final pageNum = numMatch != null ? int.parse(numMatch.group(1)!) : 0;
        if (seen.add(url)) {
          pages.add(_NumberedImage(pageNum, url));
        }
      }
    }

    // Also check for standard img tags as fallback
    if (pages.isEmpty) {
      final images = document.querySelectorAll('img');
      int idx = 0;
      for (var img in images) {
        final src = _imageAttr(img);
        if (src.isNotEmpty && _looksLikeMangaImage(src) && seen.add(src)) {
          pages.add(_NumberedImage(idx++, src));
        }
      }
    }

    pages.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
    return pages.map((p) => p.url).toList();
  }

  bool _looksLikeMangaImage(String url) {
    final lower = url.toLowerCase();
    // Filter out common non-manga images
    if (lower.contains('logo') ||
        lower.contains('favicon') ||
        lower.contains('avatar') ||
        lower.contains('banner') ||
        lower.contains('icon') ||
        lower.contains('ad') && lower.contains('banner')) {
      return false;
    }
    // Must be an image
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif') ||
        lower.contains('/storage/') ||
        lower.contains('/uploads/') ||
        lower.contains('/chapter') ||
        lower.contains('/page');
  }
}

class _NumberedImage {
  final int pageNumber;
  final String url;
  _NumberedImage(this.pageNumber, this.url);
}
