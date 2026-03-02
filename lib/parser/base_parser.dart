import 'package:manga_sonic/data/models/models.dart';
import 'package:http/http.dart' as http;
import 'package:manga_sonic/utils/cloudflare_interceptor.dart';

abstract class BaseParser {
  final String siteName;
  final String baseUrl;

  BaseParser({required this.siteName, required this.baseUrl});

  // Fetch frontpage latest or popular
  Future<List<Manga>> fetchMangaList(int page);

  // Search
  Future<List<Manga>> searchManga(String query, int page);

  // Fetch manga details (description, status, etc.)
  Future<MangaDetails> fetchMangaDetails(Manga manga);

  // Fetch chapters
  Future<List<Chapter>> fetchChapters(String mangaUrl);

  // Fetch chapter images
  Future<List<String>> fetchChapterImages(String chapterUrl);

  // Shared HTTP Client with generic User-Agent
  final http.Client client = http.Client();

  Future<http.Response> getRequest(String url) async {
    final response = await client.get(
      Uri.parse(url),
      headers: {
        ...CloudflareInterceptor.headers,
      },
    );
    
    if (response.statusCode == 403 || response.statusCode == 429) {
      throw Exception('Cloudflare block detected (Status ${response.statusCode})');
    }
    
    return response;
  }

  Future<http.Response> postRequest(String url, {Object? body, Map<String, String>? headers}) async {
    final response = await client.post(
      Uri.parse(url),
      headers: {
        ...CloudflareInterceptor.headers,
        if (headers != null) ...headers,
      },
      body: body,
    );
    
    if (response.statusCode == 403 || response.statusCode == 429) {
      throw Exception('Cloudflare block detected (Status ${response.statusCode})');
    }
    
    return response;
  }
}
