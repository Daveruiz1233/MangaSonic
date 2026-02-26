import 'package:hive/hive.dart';
import '../models/library_models.dart';

class LibraryDB {
  static const String categoryBoxName = 'categories';
  static const String itemBoxName = 'library_items';

  static Future<void> init() async {
    await Hive.openBox(categoryBoxName);
    await Hive.openBox(itemBoxName);
    if (getCategories().isEmpty) {
      addCategory(LibraryCategory(id: 'default', name: 'Default'));
    }
  }

  // Categories
  static List<LibraryCategory> getCategories() {
    final box = Hive.box(categoryBoxName);
    return box.values.map((e) => LibraryCategory.fromMap(e)).toList();
  }

  static Future<void> addCategory(LibraryCategory cat) async {
    await Hive.box(categoryBoxName).put(cat.id, cat.toMap());
  }

  static Future<void> deleteCategory(String id) async {
    if (id == 'default') return; // protect default
    await Hive.box(categoryBoxName).delete(id);
    // Remove all items in this category or move to default
    final items = getItems();
    for (var item in items) {
      if (item.categoryId == id) {
        removeItem(item.mangaUrl);
      }
    }
  }

  // Items
  static List<LibraryItem> getItems() {
    final box = Hive.box(itemBoxName);
    return box.values.map((e) => LibraryItem.fromMap(e)).toList();
  }

  static bool isSaved(String mangaUrl) {
    return Hive.box(itemBoxName).containsKey(mangaUrl);
  }

  static Future<void> saveItem(LibraryItem item) async {
    await Hive.box(itemBoxName).put(item.mangaUrl, item.toMap());
  }

  static Future<void> removeItem(String mangaUrl) async {
    await Hive.box(itemBoxName).delete(mangaUrl);
  }
}
