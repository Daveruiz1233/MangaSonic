class Manga {
  final String title;
  final String url;
  final String coverUrl;
  final String sourceId; // e.g. 'manhuatop'

  Manga({required this.title, required this.url, required this.coverUrl, required this.sourceId});

  Map<String, dynamic> toMap() => {
    'title': title,
    'url': url,
    'coverUrl': coverUrl,
    'sourceId': sourceId,
  };

  factory Manga.fromMap(Map<dynamic, dynamic> map) {
    return Manga(
      title: map['title'],
      url: map['url'],
      coverUrl: map['coverUrl'],
      sourceId: map['sourceId'],
    );
  }
}

class Chapter {
  final String title;
  final String url;
  final String mangaUrl;

  Chapter({required this.title, required this.url, required this.mangaUrl});

  Map<String, dynamic> toMap() => {
    'title': title,
    'url': url,
    'mangaUrl': mangaUrl,
  };

  factory Chapter.fromMap(Map<dynamic, dynamic> map) {
    return Chapter(
      title: map['title'],
      url: map['url'],
      mangaUrl: map['mangaUrl'],
    );
  }
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

  Map<String, dynamic> toMap() => {
    'description': description,
    'author': author,
    'artist': artist,
    'status': status,
    'genres': genres,
    'chapters': chapters.map((c) => c.toMap()).toList(),
    'suggestions': suggestions.map((s) => s.toMap()).toList(),
  };

  factory MangaDetails.fromMap(Map<dynamic, dynamic> map) {
    return MangaDetails(
      description: map['description'],
      author: map['author'],
      artist: map['artist'],
      status: map['status'],
      genres: List<String>.from(map['genres']),
      chapters: (map['chapters'] as List).map((c) => Chapter.fromMap(c)).toList(),
      suggestions: (map['suggestions'] as List).map((s) => Manga.fromMap(s)).toList(),
    );
  }
}
