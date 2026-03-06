import 'package:html/parser.dart' as parser;
import 'package:manga_sonic/data/models/models.dart';
import 'base_parser.dart';
import 'dart:convert';

class AsuraComicParser extends BaseParser {
  AsuraComicParser()
    : super(siteName: 'AsuraComic', baseUrl: 'https://asuracomic.net');

  /// Finds the main manga grid container by checking for the distinctive
  /// class combination: grid-cols-2 + md:grid-cols-5 + gap-3 + p-4.
  /// This filters out the sidebar "Popular" section and other grids.
  dynamic _findMainGrid(dynamic document) {
    final divs = document.querySelectorAll('div');
    for (var div in divs) {
      final cl = div.className.toString();
      if (cl.contains('md:grid-cols-5') &&
          cl.contains('gap-3') &&
          cl.contains('p-4')) {
        return div;
      }
    }
    return null;
  }

  List<Manga> _parseMangaGrid(dynamic container) {
    if (container == null) return [];

    final links = container.querySelectorAll('a');
    final List<Manga> list = [];

    for (var aTag in links) {
      final href = aTag.attributes['href'] ?? '';
      if (href.isEmpty || !href.contains('series/')) continue;

      final url = Uri.parse(baseUrl).resolve(href).toString();
      if (list.any((m) => m.url == url)) continue;

      // Title: span with class containing "font-bold" and "block"
      String title = '';
      final spans = aTag.querySelectorAll('span');
      for (var s in spans) {
        final cl = s.className.toString();
        if (cl.contains('block') && cl.contains('font-bold')) {
          title = s.text.trim();
          break;
        }
      }

      // Fallback: first span with font-bold that isn't a status label
      if (title.isEmpty) {
        for (var s in spans) {
          final t = s.text.trim();
          if (t.isEmpty) continue;
          if (t == 'MANHWA' ||
              t == 'MANHUA' ||
              t == 'MANGA' ||
              t == 'MANGATOON')
            continue;
          if (t == 'Ongoing' ||
              t == 'Completed' ||
              t == 'Hiatus' ||
              t == 'Dropped')
            continue;
          final cl = s.className.toString();
          if (cl.contains('font-bold') || cl.contains('font-[600]')) {
            title = t;
            break;
          }
        }
      }

      if (title.isEmpty) continue;

      // Cover image
      final img = aTag.querySelector('img');
      final coverUrl =
          img?.attributes['src'] ?? img?.attributes['data-src'] ?? '';

      list.add(
        Manga(
          title: title,
          url: url,
          coverUrl: coverUrl,
          sourceId: 'asuracomic',
        ),
      );
    }

    return list;
  }

  @override
  Future<List<Manga>> fetchMangaList(int page) async {
    final response = await getRequest('$baseUrl/series?page=$page');
    final document = parser.parse(response.body);
    final grid = _findMainGrid(document);
    return _parseMangaGrid(grid);
  }

  @override
  Future<List<Manga>> searchManga(String query, int page) async {
    final response = await getRequest('$baseUrl/series?name=$query&page=$page');
    final document = parser.parse(response.body);
    final grid = _findMainGrid(document);
    return _parseMangaGrid(grid);
  }

  @override
  Future<List<Chapter>> fetchChapters(String mangaUrl) async {
    final response = await getRequest(mangaUrl);
    final document = parser.parse(response.body);

    final chapterElements = document.querySelectorAll('a[href*="/chapter/"]');

    List<Chapter> chapters = [];
    final baseUri = Uri.parse(mangaUrl);

    for (var element in chapterElements) {
      final href = element.attributes['href'] ?? '';
      if (href.isEmpty) continue;

      final url = baseUri.resolve(href).toString();
      if (!url.contains('/chapter/')) continue;

      // Extract chapter info from h3 elements inside the link
      final h3s = element.querySelectorAll('h3');

      String chapterName = '';
      String? releaseDate;

      if (h3s.isNotEmpty) {
        chapterName = h3s.first.text.trim();
        // The first h3 is the title, the second (if exists) is often the date
        if (h3s.length > 1) {
          releaseDate = h3s[1].text.trim();
        } else {
          // Sometimes date is in a <p> or <span> sibling within the same parent
          final parent = element.parent;
          if (parent != null) {
            final dateEl = parent.querySelector('p, span:not(.font-bold)');
            if (dateEl != null && dateEl != element) {
              releaseDate = dateEl.text.trim();
            }
          }
        }
      } else {
        chapterName = element.text
            .trim()
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
      }

      // Skip promotional buttons ("First Chapter", "New Chapter")
      if (chapterName == 'First Chapter' || chapterName == 'New Chapter')
        continue;

      // Skip if chapter name is empty
      if (chapterName.isEmpty) continue;

      // Deduplicate by URL
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

  @override
  Future<MangaDetails> fetchMangaDetails(Manga manga) async {
    final response = await getRequest(manga.url);
    final document = parser.parse(response.body);

    // Description: span with color text-[#A2A2A2]
    String description = '';
    final spans = document.querySelectorAll('span');
    for (var span in spans) {
      if (span.classes.any((c) => c.contains('text-[#A2A2A2]'))) {
        final t = span.text.trim();
        if (t.length > 20) {
          // Avoid short labels
          description = t;
          break;
        }
      }
    }

    // Metadata
    String author = 'Unknown';
    String artist = 'Unknown';
    String status = 'Unknown';

    final h3s = document.querySelectorAll('h3');
    for (var i = 0; i < h3s.length; i++) {
      final text = h3s[i].text.trim().toLowerCase();
      if (text == 'author' && i + 1 < h3s.length) {
        author = h3s[i + 1].text.trim();
      } else if (text == 'artist' && i + 1 < h3s.length) {
        artist = h3s[i + 1].text.trim();
      } else if (text == 'status') {
        final container = h3s[i].parent;
        if (container != null) {
          final val = container
              .querySelectorAll('h3')
              .firstWhere(
                (e) => e != h3s[i],
                orElse: () => document.createElement('h3'),
              )
              .text
              .trim();
          if (val.isNotEmpty) status = val;
        }
      }
    }
    if (author == '_') author = 'Unknown';
    if (artist == '_') artist = 'Unknown';

    // Genres: bg-[#343434]
    List<String> genres = [];
    final buttons = document.querySelectorAll('button');
    for (var btn in buttons) {
      if (btn.classes.any((c) => c.contains('bg-[#343434]'))) {
        genres.add(btn.text.trim());
      }
    }

    final chapters = await fetchChapters(manga.url);

    // Suggestions from the "Related Series" / sidebar
    List<Manga> suggestions = [];
    final asideLinks = document.querySelectorAll('aside a[href*="series/"]');
    for (var element in asideLinks) {
      final href = element.attributes['href'] ?? '';
      final url = Uri.parse(baseUrl).resolve(href).toString();
      final title = element.querySelector('span.font-bold')?.text.trim() ?? '';
      final img = element.querySelector('img');
      final coverUrl =
          img?.attributes['src'] ?? img?.attributes['data-src'] ?? '';

      if (title.isNotEmpty &&
          !suggestions.any((m) => m.url == url) &&
          url != manga.url) {
        suggestions.add(
          Manga(
            title: title,
            url: url,
            coverUrl: coverUrl,
            sourceId: 'asuracomic',
          ),
        );
      }
      if (suggestions.length >= 6) break;
    }

    return MangaDetails(
      description: description,
      author: author,
      artist: artist,
      status: status,
      genres: genres,
      chapters: chapters,
      suggestions: suggestions,
    );
  }

  @override
  Future<List<String>> fetchChapterImages(String chapterUrl) async {
    final response = await getRequest(chapterUrl);
    final document = parser.parse(response.body);

    if (document.body?.text.contains('Login to continue reading') ?? false) {
      throw Exception('Login required to read this chapter');
    }

    // The actual chapter page images are NOT in the rendered HTML <img> tags.
    // They are embedded in the React Server Component (RSC) script payloads.
    // Real chapter pages have numeric filenames like "00-optimized.webp",
    // "01-optimized.webp", etc. Cover/thumbnail images use hash-based
    // filenames like "01K6ZFV8K4PJJPY2RGMA9RBXZP-optimized.webp".

    // Pattern: URLs with /conversions/{digits}-optimized.webp
    final pagePattern = RegExp(
      r'https?://gg\.asuracomic\.net/storage/media/\d+/conversions/(\d+)-optimized\.webp',
    );

    final Set<String> seen = {};
    final List<_NumberedImage> pages = [];

    // Search all script tags for RSC payloads
    final scripts = document.querySelectorAll('script');
    for (var script in scripts) {
      final text = script.text;
      if (!text.contains('asuracomic.net')) continue;

      for (var match in pagePattern.allMatches(text)) {
        final url = match.group(0)!;
        final pageNum = int.parse(match.group(1)!);
        if (seen.add(url)) {
          pages.add(_NumberedImage(pageNum, url));
        }
      }
    }

    // Sort by page number to ensure correct reading order (00, 01, 02, ...)
    pages.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));

    return pages.map((p) => p.url).toList();
  }
}

class _NumberedImage {
  final int pageNumber;
  final String url;
  _NumberedImage(this.pageNumber, this.url);
}
