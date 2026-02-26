import 'package:html/parser.dart' as parser;
import 'package:manga_sonic/data/models/models.dart';
import 'base_parser.dart';

class AsuraComicParser extends BaseParser {
  AsuraComicParser() : super(siteName: 'AsuraComic', baseUrl: 'https://asuracomic.net');

  @override
  Future<List<Manga>> fetchMangaList(int page) async {
    final response = await getRequest('$baseUrl/series/?page=$page');
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
  Future<List<Manga>> searchManga(String query, int page) async {
    final response = await getRequest('$baseUrl/?s=$query');
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
    
    final chapterElements = document.querySelectorAll('main a[href*="/chapter/"], .chapter-list a, .eph-num a, .chbox, .chplist a, #chapterlist a, .wp-manga-chapter a');
    
    List<Chapter> chapters = [];
    for (var element in chapterElements) {
      // Removed the narrow pl-4 filter as it might be filtering out real chapters on the new site layout
      final href = element.attributes['href'] ?? '';
      if (href.isEmpty) continue;
      
      String url = '';
      if (href.startsWith('http')) {
         url = href;
      } else {
         String relative = href.startsWith('/') ? href.substring(1) : href;
         if (!relative.startsWith('series/')) relative = 'series/' + relative;
         url = '$baseUrl/$relative';
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
  Future<List<String>> fetchChapterImages(String chapterUrl) async {
    final response = await getRequest(chapterUrl);
    final document = parser.parse(response.body);
    
    final images = document.querySelectorAll('img[src*="/storage/media/"], #readerarea img, .reading-content img');
    
    List<String> list = [];
    for (var img in images) {
      final src = img.attributes['src'] ?? img.attributes['data-src'] ?? '';
      if (src.isNotEmpty && !src.contains('thumb') && !src.contains('logo') && !src.contains('avatar')) {
        list.add(src.trim());
      }
    }
    return list;
  }
}
