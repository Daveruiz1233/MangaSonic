import 'package:html/parser.dart' as parser;
import 'package:manga_sonic/data/models/models.dart';
import 'base_parser.dart';

class AsuraComicParser extends BaseParser {
  AsuraComicParser() : super(siteName: 'AsuraComic', baseUrl: 'https://asuracomic.net');

  @override
  Future<List<Manga>> fetchMangaList(int page) async {
    // Asura now uses path-based pagination on their homepage grid
    final response = await getRequest('$baseUrl/page/$page');
    final document = parser.parse(response.body);
    
    final elements = document.querySelectorAll('a[href*="/series/"]');
    
    final Map<String, Map<String, String>> mangaMap = {};
    for (var aTag in elements) {
      final title = aTag.text.trim();
      if (title.isEmpty || title == "Series" || title.contains("Chapter")) continue; // Skip nav/chapter links

      final href = aTag.attributes['href'] ?? '';
      if (href.isEmpty) continue;
      
      final url = href.startsWith('http') ? href : (href.startsWith('/') ? '$baseUrl$href' : '$baseUrl/$href');
      
      if (!mangaMap.containsKey(url)) {
        mangaMap[url] = {'title': title, 'coverUrl': ''};
      }
      
      final img = aTag.querySelector('img');
      if (img != null) {
        final src = img.attributes['src'] ?? img.attributes['data-src'] ?? '';
        if (src.isNotEmpty && mangaMap[url]!['coverUrl']!.isEmpty) {
          mangaMap[url]!['coverUrl'] = src;
        }
      }
    }
    
    return mangaMap.entries
        .where((e) => e.value['title']!.isNotEmpty)
        .map((e) => Manga(title: e.value['title']!, url: e.key, coverUrl: e.value['coverUrl']!, sourceId: 'asuracomic'))
        .toList();
  }

  @override
  Future<List<Manga>> searchManga(String query, int page) async {
    // Asura's search endpoint currently ignores the page parameter and always returns the first 10 results.
    // Returning empty array for page > 1 prevents infinite duplicate scrolling.
    if (page > 1) {
      return [];
    }

    final response = await getRequest('$baseUrl/series?name=$query');
    final document = parser.parse(response.body);
    final elements = document.querySelectorAll('a[href*="/series/"]');
    
    final Map<String, Map<String, String>> mangaMap = {};
    for (var aTag in elements) {
      final href = aTag.attributes['href'] ?? '';
      if (href.isEmpty) continue;
      
      final url = href.startsWith('http') ? href : (href.startsWith('/') ? '$baseUrl$href' : '$baseUrl/$href');
      
      if (!mangaMap.containsKey(url)) {
        mangaMap[url] = {'title': '', 'coverUrl': ''};
      }
      
      final title = aTag.text.trim();
      if (title.isNotEmpty && mangaMap[url]!['title']!.isEmpty) {
        mangaMap[url]!['title'] = title;
      }
      
      final img = aTag.querySelector('img');
      if (img != null) {
        final src = img.attributes['src'] ?? img.attributes['data-src'] ?? '';
        if (src.isNotEmpty && mangaMap[url]!['coverUrl']!.isEmpty) {
          mangaMap[url]!['coverUrl'] = src;
        }
      }
    }
    
    return mangaMap.entries
        .where((e) => e.value['title']!.isNotEmpty)
        .map((e) => Manga(title: e.value['title']!, url: e.key, coverUrl: e.value['coverUrl']!, sourceId: 'asuracomic'))
        .toList();
  }

  @override
  Future<List<Chapter>> fetchChapters(String mangaUrl) async {
    final response = await getRequest(mangaUrl);
    final document = parser.parse(response.body);
    
    final chapterElements = document.querySelectorAll('main a[href*="/chapter/"], a[href*="/chapter/"], .chapter-list a, .eph-num a, .chbox, .chplist a, #chapterlist a, .wp-manga-chapter a');
    
    List<Chapter> chapters = [];
    for (var element in chapterElements) {
      final href = element.attributes['href'] ?? '';
      if (href.isEmpty) continue;
      
      String url = '';
      if (href.startsWith('http')) {
         url = href;
      } else {
         if (href.startsWith('/')) {
            url = '$baseUrl$href';
         } else {
            // Handle relative links like "pick-me-up.../chapter/190"
            // Ensure mangaUrl ends with a slash for correct resolution
            final base = mangaUrl.endsWith('/') ? mangaUrl : '$mangaUrl/';
            url = Uri.parse(base).resolve(href).toString();
         }
      }

      // Filter: Ensure the URL belongs to this manga and contains "/chapter/"
      final mangaSlug = mangaUrl.split('/').lastWhere((s) => s.isNotEmpty);
      if (!url.contains(mangaSlug) || !url.contains('/chapter/')) continue;

      final title = element.text.trim().replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      
      if (url.isNotEmpty && !chapters.any((c) => c.url == url)) {
        chapters.add(Chapter(title: title, url: url, mangaUrl: mangaUrl));
      }
    }
    return chapters;
  }

  @override
  Future<MangaDetails> fetchMangaDetails(Manga manga) async {
    final response = await getRequest(manga.url);
    final document = parser.parse(response.body);

    // Title and Cover from existing manga object if possible, 
    // but we can also re-extract them to be sure.
    
    // Description
    String description = '';
    final synopsisHeader = document.querySelectorAll('h3, span').firstWhere(
      (e) => e.text.contains('Synopsis'),
      orElse: () => document.createElement('div'),
    );
    if (synopsisHeader.text.contains('Synopsis')) {
      final descElements = synopsisHeader.parent?.querySelectorAll('span') ?? [];
      for (var element in descElements) {
        if (element.classes.contains('text-[#A2A2A2]')) {
          description = element.text.trim();
          break;
        }
      }
    }

    // Metadata (Author, Artist, Status)
    String author = 'Unknown';
    String artist = 'Unknown';
    String status = 'Unknown';

    final metadataElements = document.querySelectorAll('h3.text-sm');
    for (var i = 0; i < metadataElements.length; i++) {
      final text = metadataElements[i].text.trim();
      if (text == 'Author' && i + 1 < metadataElements.length) {
        author = metadataElements[i + 1].text.trim();
      } else if (text == 'Artist' && i + 1 < metadataElements.length) {
        artist = metadataElements[i + 1].text.trim();
      } else if (text == 'Status' && i + 1 < metadataElements.length) {
        status = metadataElements[i + 1].text.trim();
      }
    }

    // Genres
    List<String> genres = [];
    final genreElements = document.querySelectorAll('button.text-white, a.text-white, span.text-white');
    for (var element in genreElements) {
      if (element.classes.contains('bg-[#343434]')) {
        genres.add(element.text.trim());
      }
    }

    // Chapters
    final chapters = await fetchChapters(manga.url);

    // Suggestions (Popular Today or Related)
    List<Manga> suggestions = [];
    final suggestionElements = document.querySelectorAll('aside a[href*="/series/"]');
    for (var element in suggestionElements) {
      final href = element.attributes['href'] ?? '';
      final url = href.startsWith('http') ? href : '$baseUrl$href';
      final title = element.querySelector('span.font-bold')?.text.trim() ?? '';
      final coverUrl = element.querySelector('img')?.attributes['src'] ?? '';
      
      if (title.isNotEmpty && !suggestions.any((m) => m.url == url) && url != manga.url) {
        suggestions.add(Manga(title: title, url: url, coverUrl: coverUrl, sourceId: 'asuracomic'));
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
    
    final images = document.querySelectorAll('div.flex.flex-col.items-center.justify-center img, #readerarea img');
    
    List<String> list = [];
    for (var img in images) {
      final src = img.attributes['src'] ?? img.attributes['data-src'] ?? '';
      if (src.isNotEmpty && 
          !src.contains('thumb') && 
          !src.contains('logo') && 
          !src.contains('avatar') &&
          !src.contains('discord') &&
          src.contains('/storage/media/')) {
        list.add(src.trim());
      }
    }
    return list;
  }
}
