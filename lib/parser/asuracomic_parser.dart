import 'package:html/parser.dart' as parser;
import 'package:manga_sonic/data/models/models.dart';
import 'base_parser.dart';
import 'dart:convert';

class AsuraComicParser extends BaseParser {
  AsuraComicParser()
    : super(siteName: 'AsuraComic', baseUrl: 'https://asurascans.com');

  /// Finds the main manga grid container by checking for the distinctive
  /// class combination: grid-cols-2 + md:grid-cols-5 + gap-3 + p-4.
  /// This filters out the sidebar "Popular" section and other grids.
  dynamic _findMainGrid(dynamic document) {
    // In the new Astro site, the grid doesn't have a single unique "grid-cols-X" container 
    // that's easy to target consistently. Instead, we'll look for the container 
    // that holds multiple manga link tags.
    final items = document.querySelectorAll('a[href*="/comics/"]');
    if (items.isNotEmpty) return document; // Return document as "container" and parse all links
    return null;
  }

  List<Manga> _parseMangaGrid(dynamic container) {
    if (container == null) return [];

    final List<Manga> list = [];

    // The new site uses /comics/ prefixed links for series
    // Look for the card containers
    final cards = container.querySelectorAll('.series-card');
    if (cards.isNotEmpty) {
      for (var card in cards) {
        final links = card.querySelectorAll('a[href*="/comics/"]');
        if (links.isEmpty) continue;

        final aTag = links.first;
        final href = aTag.attributes['href'] ?? '';
        final url = Uri.parse(baseUrl).resolve(href).toString();
        if (list.any((m) => m.url == url)) continue;

        String title = '';
        String coverUrl = '';

        // Title is usually in an h3 within one of the links
        for (var link in links) {
          final h3 = link.querySelector('h3');
          if (h3 != null) {
            title = h3.text.trim();
            break;
          }
        }

        // Cover is usually in an img within one of the links
        for (var link in links) {
          final img = link.querySelector('img');
          if (img != null) {
            coverUrl = img.attributes['src'] ?? img.attributes['data-src'] ?? '';
            if (coverUrl.isNotEmpty) break;
          }
        }

        // Fallback for title
        if (title.isEmpty) {
          for (var link in links) {
            final spans = link.querySelectorAll('span');
            for (var s in spans) {
              final t = s.text.trim();
              if (t.isNotEmpty && t != 'Manga' && t != 'Manhwa' && t != 'Manhua' && !t.contains('.')) {
                title = t;
                break;
              }
            }
            if (title.isNotEmpty) break;
          }
        }

        if (title.isNotEmpty) {
          list.add(
            Manga(
              title: title,
              url: url,
              coverUrl: coverUrl,
              sourceId: 'asuracomic',
            ),
          );
        }
      }
    } else {
      // Fallback to original link-based approach if .series-card is not found
      final links = container.querySelectorAll('a[href*="/comics/"]');
      for (var aTag in links) {
        final href = aTag.attributes['href'] ?? '';
        if (href.isEmpty) continue;

        final url = Uri.parse(baseUrl).resolve(href).toString();
        if (list.any((m) => m.url == url)) continue;

        String title = '';
        final h3 = aTag.querySelector('h3');
        if (h3 != null) {
          title = h3.text.trim();
        }

        if (title.isEmpty) {
          final spans = aTag.querySelectorAll('span');
          for (var s in spans) {
            final t = s.text.trim();
            if (t.isEmpty || t == 'Manga' || t == 'Manhwa' || t == 'Manhua' || t.contains('.')) continue;
            title = t;
            break;
          }
        }

        final img = aTag.querySelector('img');
        final coverUrl = img?.attributes['src'] ?? img?.attributes['data-src'] ?? '';

        if (title.isNotEmpty) {
          list.add(
            Manga(
              title: title,
              url: url,
              coverUrl: coverUrl,
              sourceId: 'asuracomic',
            ),
          );
        }
      }
    }

    return list;
  }

  @override
  Future<List<Manga>> fetchMangaList(int page) async {
    // The new site uses /comics for listing
    final response = await getRequest('$baseUrl/comics?page=$page');
    final document = parser.parse(response.body);
    final grid = _findMainGrid(document);
    return _parseMangaGrid(grid);
  }

  @override
  Future<List<Manga>> searchManga(String query, int page) async {
    // Search is also integrated into /comics or /search
    final response = await getRequest('$baseUrl/comics?q=$query&page=$page');
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

    // Description: Look for div with id="description-text"
    String description = '';
    final descDiv = document.querySelector('#description-text');
    if (descDiv != null) {
      description = descDiv.text.trim();
    } else {
      // Fallback to p tags with specific style
      final pTags = document.querySelectorAll('p');
      for (var p in pTags) {
        if (p.classes.any((c) => c.contains('text-white/80'))) {
          description = p.text.trim();
          break;
        }
      }
    }

    // Metadata
    String author = 'Unknown';
    String artist = 'Unknown';
    String status = 'Unknown';

    final textNodes = document.querySelectorAll('div, span, p');
    for (var node in textNodes) {
      final text = node.text.trim().toLowerCase();
      if (text == 'author' && node.nextElementSibling != null) {
        author = node.nextElementSibling!.text.trim();
      } else if (text == 'artist' && node.nextElementSibling != null) {
        artist = node.nextElementSibling!.text.trim();
      } else if (text == 'status' && node.nextElementSibling != null) {
        status = node.nextElementSibling!.text.trim();
      }
    }

    // Genres: tags with bg-white/5
    List<String> genres = [];
    final anchors = document.querySelectorAll('a');
    for (var a in anchors) {
      if (a.classes.any((c) => c.contains('bg-white/5')) || a.classes.any((c) => c.contains('rounded-lg'))) {
        final g = a.text.trim();
        if (g.length < 20 && !g.contains('Chapter') && !g.contains('Home')) {
          genres.add(g);
        }
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
      title: manga.title,
      coverUrl: manga.coverUrl,
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

    // Look for the Astro component that contains the chapter images
    final List<String> imageUrls = [];
    
    // Find <astro-island> that likely contains the ChapterReader component
    final islands = document.querySelectorAll('astro-island');
    for (var island in islands) {
      final propsString = island.attributes['props'] ?? '';
      final componentUrl = island.attributes['component-url'] ?? '';
      final componentExport = island.attributes['component-export'] ?? '';
      
      if (propsString.isNotEmpty && (componentUrl.contains('ChapterReader') || componentExport == 'ChapterReader')) {
        try {
          // Astro props are HTML entities encoded JSON
          final decodedProps = _unescapeHtml(propsString);
          final Map<String, dynamic> props = json.decode(decodedProps);
          
          // Current Astro structure: pages[1][index][1].url[1]
          final pagesData = props['pages'];
          if (pagesData is List && pagesData.length > 1) {
            final pagesList = pagesData[1];
            if (pagesList is List) {
              for (var pageItem in pagesList) {
                if (pageItem is List && pageItem.length > 1) {
                  final pageObj = pageItem[1];
                  if (pageObj is Map && pageObj.containsKey('url')) {
                    final urlData = pageObj['url'];
                    String? url;
                    if (urlData is List && urlData.length > 1) {
                      url = urlData[1].toString();
                    } else if (urlData is String) {
                      url = urlData;
                    }
                    if (url != null && url.isNotEmpty) imageUrls.add(url);
                  }
                }
              }
            }
          }
        } catch (e) {
          // Silent or print if debugging
        }
      }
    }

    // Fallback 1: standard <img> tags
    if (imageUrls.isEmpty) {
      final imgs = document.querySelectorAll('img');
      for (var img in imgs) {
        final src = img.attributes['src'] ?? img.attributes['data-src'] ?? '';
        if (src.contains('/asura-images/chapters/') || src.contains('gg.asuracomic.net/storage/media/')) {
          imageUrls.add(src);
        }
      }
    }

    // Fallback 2: Regex search in the whole body text/html
    if (imageUrls.isEmpty) {
      final bodyHtml = response.body;
      final chapterImagePattern = RegExp(
        r'https?://[^\s"''<>]+?/asura-images/chapters/[^\s"''<>]+?\.webp',
        caseSensitive: false,
      );
      for (var match in chapterImagePattern.allMatches(bodyHtml)) {
        imageUrls.add(match.group(0)!);
      }
    }

    // Deduplicate and filter out empty
    return imageUrls.where((url) => url.isNotEmpty).toSet().toList();
  }

  String _unescapeHtml(String input) {
    return input
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&#39;', "'")
        .replaceAll('&#x2F;', '/');
  }
}

class _NumberedImage {
  final int pageNumber;
  final String url;
  _NumberedImage(this.pageNumber, this.url);
}
