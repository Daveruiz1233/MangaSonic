import 'package:hive/hive.dart';

class DownloadedChapter {
  final String chapterUrl;
  final String chapterTitle;
  final String mangaTitle;
  final String mangaUrl;
  final String directoryPath;
  final int imageCount;

  DownloadedChapter({
    required this.chapterUrl,
    required this.chapterTitle,
    required this.mangaTitle,
    required this.mangaUrl,
    required this.directoryPath,
    required this.imageCount,
  });

  Map<String, dynamic> toMap() => {
    'chapterUrl': chapterUrl,
    'chapterTitle': chapterTitle,
    'mangaTitle': mangaTitle,
    'mangaUrl': mangaUrl,
    'directoryPath': directoryPath,
    'imageCount': imageCount,
  };

  factory DownloadedChapter.fromMap(Map<dynamic, dynamic> map) {
    return DownloadedChapter(
      chapterUrl: map['chapterUrl'],
      chapterTitle: map['chapterTitle'],
      mangaTitle: map['mangaTitle'],
      mangaUrl: map['mangaUrl'],
      directoryPath: map['directoryPath'],
      imageCount: map['imageCount'],
    );
  }
}

class DownloadDB {
  static const String downloadBoxName = 'downloads';

  static Future<void> init() async {
    await Hive.openBox(downloadBoxName);
  }

  static List<DownloadedChapter> getDownloads() {
    final box = Hive.box(downloadBoxName);
    return box.values.map((e) => DownloadedChapter.fromMap(e)).toList();
  }

  static bool isDownloaded(String chapterUrl) {
    return Hive.box(downloadBoxName).containsKey(chapterUrl);
  }

  static DownloadedChapter? getDownload(String chapterUrl) {
    if (!isDownloaded(chapterUrl)) return null;
    return DownloadedChapter.fromMap(Hive.box(downloadBoxName).get(chapterUrl));
  }

  static Future<void> saveDownload(DownloadedChapter chapter) async {
    await Hive.box(downloadBoxName).put(chapter.chapterUrl, chapter.toMap());
  }

  static Future<void> removeDownload(String chapterUrl) async {
    await Hive.box(downloadBoxName).delete(chapterUrl);
  }
}
