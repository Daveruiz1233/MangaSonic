class Manga {
  final String title;
  final String url;
  final String coverUrl;
  final String sourceId; // e.g. 'manhuatop'

  Manga({required this.title, required this.url, required this.coverUrl, required this.sourceId});
}

class Chapter {
  final String title;
  final String url;
  final String mangaUrl;

  Chapter({required this.title, required this.url, required this.mangaUrl});
}
