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

  ChapterStatus({required this.chapterUrl, this.isRead = false, this.lastPage = 0});

  Map<String, dynamic> toMap() => {
    'chapterUrl': chapterUrl,
    'isRead': isRead,
    'lastPage': lastPage,
  };

  factory ChapterStatus.fromMap(Map<dynamic, dynamic> map) {
    return ChapterStatus(
      chapterUrl: map['chapterUrl'],
      isRead: map['isRead'] ?? false,
      lastPage: map['lastPage'] ?? 0,
    );
  }
}
