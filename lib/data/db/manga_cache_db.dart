import 'package:hive/hive.dart';
import '../models/models.dart';

class MangaCacheDB {
  static const String cacheBoxName = 'manga_details_cache';

  static Future<void> init() async {
    await Hive.openBox(cacheBoxName);
  }

  static Future<void> saveDetails(String mangaUrl, MangaDetails details) async {
    final box = Hive.box(cacheBoxName);
    await box.put(mangaUrl, details.toMap());
  }

  static MangaDetails? getDetails(String mangaUrl) {
    final box = Hive.box(cacheBoxName);
    final data = box.get(mangaUrl);
    if (data == null) return null;
    try {
      return MangaDetails.fromMap(data);
    } catch (e) {
      print('Error parsing cached manga details: $e');
      return null;
    }
  }

  static Future<void> clearCache() async {
    await Hive.box(cacheBoxName).clear();
  }
}
