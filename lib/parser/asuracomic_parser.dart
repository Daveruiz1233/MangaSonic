import 'package:html/parser.dart' as parser;
import 'package:manga_sonic/data/models/models.dart';
import 'base_parser.dart';

class AsuraComicParser extends BaseParser {
  AsuraComicParser() : super(siteName: 'AsuraComic', baseUrl: 'https://asuracomic.net');

  @override
  Future<List<Manga>> fetchMangaList(int page) async {
    final response = await getRequest('$baseUrl/manga/?page=$page');
    final document = parser.parse(response.body);
    // AsuraComic often uses .bsx or .listupd containers for manga items
    final elements = document.querySelectorAll('.bsx, .luf, .listupd .item, .page-item-detail, a[href^="/series/"]');
    
    List<Manga> list = [];
    for (var element in elements) {
      final aTag = element.localName == 'a' ? element : element.querySelector('a');
      final imgTag = element.querySelector('img');
      if (aTag != null && imgTag != null) {
        final href = aTag.attributes['href'] ?? '';
        final url = href.startsWith('http') ? href : '$baseUrl$href';
        
        final title = aTag.attributes['title'] ?? imgTag.attributes['alt'] ?? imgTag.attributes['title'] ?? element.text.trim();
        final coverUrl = imgTag.attributes['src'] ?? imgTag.attributes['data-src'] ?? '';
        
        if (url.isNotEmpty && title.isNotEmpty && !list.any((m) => m.url == url)) {
          list.add(Manga(title: title.trim(), url: url, coverUrl: coverUrl, sourceId: 'asuracomic'));
        }
      }
    }
    return list;
  }

  @override
  Future<List<Manga>> searchManga(String query, int page) async {
    final response = await getRequest('$baseUrl/?s=$query');
    final document = parser.parse(response.body);
    final elements = document.querySelectorAll('.bsx, .luf, .listupd .item, a[href^="/series/"]');
    
    List<Manga> list = [];
    for (var element in elements) {
      final aTag = element.localName == 'a' ? element : element.querySelector('a');
      final imgTag = element.querySelector('img');
      if (aTag != null && imgTag != null) {
        final href = aTag.attributes['href'] ?? '';
        final url = href.startsWith('http') ? href : '$baseUrl$href';
        
        final title = aTag.attributes['title'] ?? imgTag.attributes['alt'] ?? element.text.trim();
        final coverUrl = imgTag.attributes['src'] ?? imgTag.attributes['data-src'] ?? '';
        
        if (url.isNotEmpty && title.isNotEmpty && !list.any((m) => m.url == url)) {
          list.add(Manga(title: title.trim(), url: url, coverUrl: coverUrl, sourceId: 'asuracomic'));
        }
      }
    }
    return list;
  }

  @override
  Future<List<Chapter>> fetchChapters(String mangaUrl) async {
    final response = await getRequest(mangaUrl);
    final document = parser.parse(response.body);
    
    final chapterElements = document.querySelectorAll('.eph-num a, .chbox, .chplist a, #chapterlist a, .wp-manga-chapter a');
    
    List<Chapter> chapters = [];
    for (var element in chapterElements) {
      final href = element.attributes['href'] ?? '';
      final url = href.startsWith('http') ? href : '$baseUrl$href';
      final title = element.text.trim();
      
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
    
    final images = document.querySelectorAll('#readerarea img, .reading-content img');
    
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
