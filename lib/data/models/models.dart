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

class ChapterStatus {
  final String chapterUrl;
  final bool isRead;
  final int lastPage;
  final double lastPageOffset;

  ChapterStatus({required this.chapterUrl, this.isRead = false, this.lastPage = 0, this.lastPageOffset = 0.0});

  Map<String, dynamic> toMap() => {
    'chapterUrl': chapterUrl,
    'isRead': isRead,
    'lastPage': lastPage,
    'lastPageOffset': lastPageOffset,
  };

  factory ChapterStatus.fromMap(Map<dynamic, dynamic> map) {
    return ChapterStatus(
      chapterUrl: map['chapterUrl'],
      isRead: map['isRead'] ?? false,
      lastPage: map['lastPage'] ?? 0,
      lastPageOffset: (map['lastPageOffset'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class MangaDetails {
  final String description;
  final String author;
  final String artist;
  final String status;
  final List<String> genres;
  final List<Chapter> chapters;
  final List<Manga> suggestions;

  MangaDetails({
    required this.description,
    required this.author,
    required this.artist,
    required this.status,
    required this.genres,
    required this.chapters,
    required this.suggestions,
  });
}
