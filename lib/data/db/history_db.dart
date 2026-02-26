import 'package:hive/hive.dart';
import '../models/models.dart';

class HistoryDB {
  static const String statusBoxName = 'chapter_statuses';

  static Future<void> init() async {
    await Hive.openBox(statusBoxName);
  }

  static bool isRead(String chapterUrl) {
    final box = Hive.box(statusBoxName);
    final data = box.get(chapterUrl);
    if (data == null) return false;
    return ChapterStatus.fromMap(data).isRead;
  }

  static Future<void> markAsRead(String chapterUrl, {bool isRead = true}) async {
    final box = Hive.box(statusBoxName);
    final status = ChapterStatus(chapterUrl: chapterUrl, isRead: isRead);
    await box.put(chapterUrl, status.toMap());
  }

  static Future<void> saveProgress(String chapterUrl, int lastPage) async {
    final box = Hive.box(statusBoxName);
    final existing = box.get(chapterUrl);
    bool read = false;
    if (existing != null) {
      read = ChapterStatus.fromMap(existing).isRead;
    }
    final status = ChapterStatus(chapterUrl: chapterUrl, isRead: read, lastPage: lastPage);
    await box.put(chapterUrl, status.toMap());
  }

  static int getLastPage(String chapterUrl) {
    final box = Hive.box(statusBoxName);
    final data = box.get(chapterUrl);
    if (data == null) return 0;
    return ChapterStatus.fromMap(data).lastPage;
  }
}
