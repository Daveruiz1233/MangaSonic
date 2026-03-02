import 'package:html/parser.dart' as parser;
import 'package:manga_sonic/data/models/models.dart';
import 'package:flutter/foundation.dart';
import 'base_parser.dart';

class ManhuaTopParser extends BaseParser {
  ManhuaTopParser() : super(siteName: 'ManhuaTop', baseUrl: 'https://manhuatop.org');

  @override
  Future<List<Manga>> fetchMangaList(int page) async {
    final response = await getRequest(page == 1 ? '$baseUrl/manga/' : '$baseUrl/manga/page/$page/');
    final document = parser.parse(response.body);
    final elements = document.querySelectorAll('.page-item-detail, .c-tabs-item__content, .item');
    
    List<Manga> list = [];
    for (var element in elements) {
      final aTag = element.querySelector('a');
      final imgTag = element.querySelector('img');
      if (aTag != null && imgTag != null) {
        final url = aTag.attributes['href'] ?? '';
        final title = aTag.attributes['title'] ?? imgTag.attributes['alt'] ?? '';
        final coverUrl = imgTag.attributes['src'] ?? imgTag.attributes['data-src'] ?? '';
        if (url.isNotEmpty && title.isNotEmpty) {
          list.add(Manga(title: title.trim(), url: url, coverUrl: coverUrl, sourceId: 'manhuatop'));
        }
      }
    }
    return list;
  }

  @override
  Future<List<Manga>> searchManga(String query, int page) async {
    final response = await getRequest(page == 1 ? '$baseUrl/?s=$query&post_type=wp-manga' : '$baseUrl/page/$page/?s=$query&post_type=wp-manga');
    final document = parser.parse(response.body);
    final elements = document.querySelectorAll('.c-tabs-item__content');
    
    List<Manga> list = [];
    // (similar parsing logic here)
    for (var element in elements) {
      final aTag = element.querySelector('a');
      final imgTag = element.querySelector('img');
      if (aTag != null && imgTag != null) {
        final url = aTag.attributes['href'] ?? '';
        final title = aTag.attributes['title'] ?? imgTag.attributes['alt'] ?? '';
        final coverUrl = imgTag.attributes['src'] ?? imgTag.attributes['data-src'] ?? '';
        if (url.isNotEmpty && title.isNotEmpty) {
          list.add(Manga(title: title.trim(), url: url, coverUrl: coverUrl, sourceId: 'manhuatop'));
        }
      }
    }
    return list;
  }

  @override
  Future<MangaDetails> fetchMangaDetails(Manga manga) async {
    final chapters = await fetchChapters(manga.url);
    return MangaDetails(
      description: 'Description not supported yet for this source.',
      author: 'Unknown',
      artist: 'Unknown',
      status: 'Unknown',
      genres: [],
      chapters: chapters,
      suggestions: [],
    );
  }

  @override
  Future<List<Chapter>> fetchChapters(String mangaUrl) async {
    // Madara sites usually have a chapters list or require a POST to ajax
    // For simplicity, we try direct fetch first, and fallback to ajax
    var response = await getRequest(mangaUrl);
    var document = parser.parse(response.body);
    
    // Sometimes it's loaded via POST to admin-ajax.php, but let's see if we can find it
    var chapterElements = document.querySelectorAll('.wp-manga-chapter a');
    
    if (chapterElements.isEmpty) {
      // Trying the Madara /ajax/chapters/ route (often used in newer Madara versions)
      final ajaxUrl = mangaUrl.endsWith('/') ? '${mangaUrl}ajax/chapters/' : '$mangaUrl/ajax/chapters/';
      try {
        response = await postRequest(
          ajaxUrl,
          headers: {'X-Requested-With': 'XMLHttpRequest'},
        );
        if (response.statusCode == 200) {
          document = parser.parse(response.body);
          chapterElements = document.querySelectorAll('.wp-manga-chapter a');
        }
      } catch (e) {
        debugPrint('Ajax/chapters/ failed: $e');
      }
    }

    if (chapterElements.isEmpty) {
      // Trying the Admin-Ajax fallback
      final idTag = document.querySelector('#manga-chapters-holder');
      final mangaId = idTag?.attributes['data-id'];
      if (mangaId != null) {
        response = await postRequest(
          '$baseUrl/wp-admin/admin-ajax.php',
          body: { 'action': 'manga_get_chapters', 'manga': mangaId },
          headers: {'X-Requested-With': 'XMLHttpRequest'},
        );
        document = parser.parse(response.body);
        chapterElements = document.querySelectorAll('.wp-manga-chapter a');
      }
    }

    List<Chapter> chapters = [];
    for (var element in chapterElements) {
      final url = element.attributes['href'] ?? '';
      final title = element.text.trim();
      if (url.isNotEmpty) {
        chapters.add(Chapter(title: title, url: url, mangaUrl: mangaUrl));
      }
    }
    // WP-Manga usually lists latest first. We'll return it as is.
    return chapters;
  }

  @override
  Future<List<String>> fetchChapterImages(String chapterUrl) async {
    final response = await getRequest(chapterUrl);
    final document = parser.parse(response.body);
    final images = document.querySelectorAll('.page-break img, .reading-content img');
    
    List<String> list = [];
    for (var img in images) {
      final src = img.attributes['data-src'] ?? img.attributes['src'] ?? '';
      if (src.isNotEmpty) {
        list.add(src.trim());
      }
    }
    return list;
  }
}
