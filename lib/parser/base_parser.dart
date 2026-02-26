import 'package:manga_sonic/data/models/models.dart';
import 'package:http/http.dart' as http;

abstract class BaseParser {
  final String siteName;
  final String baseUrl;

  BaseParser({required this.siteName, required this.baseUrl});

  // Fetch frontpage latest or popular
  Future<List<Manga>> fetchMangaList(int page);

  // Search
  Future<List<Manga>> searchManga(String query, int page);

  // Fetch manga details (chapters)
  Future<List<Chapter>> fetchChapters(String mangaUrl);

  // Fetch chapter images
  Future<List<String>> fetchChapterImages(String chapterUrl);

  // Shared HTTP Client with generic User-Agent
  final http.Client client = http.Client();

  Future<http.Response> getRequest(String url) {
    return client.get(
      Uri.parse(url),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
      },
    );
  }
}
