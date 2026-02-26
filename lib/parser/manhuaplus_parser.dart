import 'package:html/parser.dart' as parser;
import 'package:manga_sonic/data/models/models.dart';
import 'base_parser.dart';

class ManhuaPlusParser extends BaseParser {
  ManhuaPlusParser() : super(siteName: 'ManhuaPlus', baseUrl: 'https://manhuaplus.com');

  @override
  Future<List<Manga>> fetchMangaList(int page) async {
    final response = await getRequest('$baseUrl/manga/?page=$page');
    final document = parser.parse(response.body);
    final elements = document.querySelectorAll('.page-item-detail, .c-tabs-item__content, .item');
    
    List<Manga> list = [];
    for (var element in elements) {
      final aTag = element.querySelector('a');
      final imgTag = element.querySelector('img');
      if (aTag != null && imgTag != null) {
        final url = aTag.attributes['href'] ?? '';
        final title = aTag.attributes['title'] ?? imgTag.attributes['alt'] ?? '';
        final coverUrl = imgTag.attributes['data-src'] ?? imgTag.attributes['data-lazy-src'] ?? imgTag.attributes['src'] ?? '';
        
        if (url.isNotEmpty && title.isNotEmpty) {
          list.add(Manga(title: title.trim(), url: url, coverUrl: coverUrl, sourceId: 'manhuaplus'));
        }
      }
    }
    return list;
  }

  @override
  Future<List<Manga>> searchManga(String query, int page) async {
    final response = await getRequest('$baseUrl/?s=$query&post_type=wp-manga');
    final document = parser.parse(response.body);
    final elements = document.querySelectorAll('.c-tabs-item__content');
    
    List<Manga> list = [];
    for (var element in elements) {
      final aTag = element.querySelector('a');
      final imgTag = element.querySelector('img');
      if (aTag != null && imgTag != null) {
        final url = aTag.attributes['href'] ?? '';
        final title = aTag.attributes['title'] ?? imgTag.attributes['alt'] ?? '';
        final coverUrl = imgTag.attributes['data-src'] ?? imgTag.attributes['data-lazy-src'] ?? imgTag.attributes['src'] ?? '';
        
        if (url.isNotEmpty && title.isNotEmpty) {
          list.add(Manga(title: title.trim(), url: url, coverUrl: coverUrl, sourceId: 'manhuaplus'));
        }
      }
    }
    return list;
  }

  @override
  Future<List<Chapter>> fetchChapters(String mangaUrl) async {
    var response = await getRequest(mangaUrl);
    var document = parser.parse(response.body);
    
    var chapterElements = document.querySelectorAll('.wp-manga-chapter a');
    
    if (chapterElements.isEmpty) {
      final idTag = document.querySelector('#manga-chapters-holder');
      final mangaId = idTag?.attributes['data-id'];
      if (mangaId != null) {
         response = await client.post(
           Uri.parse('$baseUrl/wp-admin/admin-ajax.php'),
           body: { 'action': 'manga_get_chapters', 'manga': mangaId }
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
    return chapters;
  }

  @override
  Future<List<String>> fetchChapterImages(String chapterUrl) async {
    final response = await getRequest(chapterUrl);
    final document = parser.parse(response.body);
    final images = document.querySelectorAll('.page-break img, .reading-content img');
    
    List<String> list = [];
    for (var img in images) {
      final src = img.attributes['data-src'] ?? img.attributes['data-lazy-src'] ?? img.attributes['src'] ?? '';
      if (src.isNotEmpty) {
        list.add(src.trim());
      }
    }
    return list;
  }
}
