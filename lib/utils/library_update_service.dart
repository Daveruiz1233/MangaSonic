import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:manga_sonic/data/db/library_db.dart';
import 'package:manga_sonic/data/db/manga_cache_db.dart';
import 'package:manga_sonic/data/models/models.dart';
import 'package:manga_sonic/parser/asuracomic_parser.dart';
import 'package:manga_sonic/parser/manhuatop_parser.dart';
import 'package:manga_sonic/parser/manhuaplus_parser.dart';
import 'package:hive/hive.dart';

class LibraryUpdateService extends ChangeNotifier {
  static const String updateBoxName = 'unread_updates';
  bool _isUpdating = false;
  String _currentManga = '';

  bool get isUpdating => _isUpdating;
  String get currentManga => _currentManga;

  static Future<void> init() async {
    await Hive.openBox(updateBoxName);
  }

  Future<void> checkForUpdates() async {
    if (_isUpdating) return;
    _isUpdating = true;
    notifyListeners();

    try {
      final items = LibraryDB.getItems();
      final updateBox = Hive.box(updateBoxName);

      for (var item in items) {
        _currentManga = item.title;
        notifyListeners();

        final parser = _getParser(item.sourceId);
        if (parser == null) continue;

        try {
          final freshDetails = await parser.getMangaDetails(item.mangaUrl);
          final cachedDetails = MangaCacheDB.getDetails(item.mangaUrl);

          if (cachedDetails != null) {
            // Check for new chapters
            final hasNew = freshDetails.chapters.length > cachedDetails.chapters.length;
            if (hasNew) {
              await updateBox.put(item.mangaUrl, true);
            }
          }
          
          // Always update cache with fresh data
          await MangaCacheDB.saveDetails(item.mangaUrl, freshDetails);
        } catch (e) {
          debugPrint('Error updating ${item.title}: $e');
        }
      }
    } finally {
      _isUpdating = false;
      _currentManga = '';
      notifyListeners();
    }
  }

  dynamic _getParser(String sourceId) {
    switch (sourceId) {
      case 'asura': return AsuraComicParser();
      case 'manhuatop': return ManhuaTopParser();
      case 'manhuaplus': return ManhuaPlusParser();
      default: return null;
    }
  }

  static bool hasUpdate(String mangaUrl) {
    return Hive.box(updateBoxName).get(mangaUrl, defaultValue: false) as bool;
  }

  static Future<void> markRead(String mangaUrl) async {
    await Hive.box(updateBoxName).delete(mangaUrl);
  }
}
