import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:manga_sonic/data/db/download_db.dart';
import 'package:manga_sonic/utils/parser_factory.dart';

class DownloadTask {
  final String chapterUrl;
  final String chapterTitle;
  final String mangaTitle;
  final String mangaUrl;
  final String sourceId;

  DownloadTask({
    required this.chapterUrl,
    required this.chapterTitle,
    required this.mangaTitle,
    required this.mangaUrl,
    required this.sourceId,
  });
}

class DownloadManager {
  static final List<DownloadTask> _queue = [];
  static bool _isProcessing = false;
  static final http.Client _client = http.Client();

  static Future<void> downloadChapter({
    required String chapterUrl,
    required String chapterTitle,
    required String mangaTitle,
    required String mangaUrl,
    required String sourceId,
  }) async {
    if (DownloadDB.isDownloaded(chapterUrl)) return;
    
    // Check if already in queue
    if (_queue.any((task) => task.chapterUrl == chapterUrl)) return;

    _queue.add(DownloadTask(
      chapterUrl: chapterUrl,
      chapterTitle: chapterTitle,
      mangaTitle: mangaTitle,
      mangaUrl: mangaUrl,
      sourceId: sourceId,
    ));

    if (!_isProcessing) {
      _processQueue();
    }
  }

  static Future<void> _processQueue() async {
    if (_queue.isEmpty) {
      _isProcessing = false;
      return;
    }

    _isProcessing = true;
    final task = _queue.first;

    try {
      await _executeTask(task);
    } catch (e) {
      print('Error processing task ${task.chapterTitle}: $e');
    }

    _queue.removeAt(0);
    _processQueue();
  }

  static Future<void> _executeTask(DownloadTask task) async {
    final parser = getParserForSite(task.sourceId);
    final imageUrls = await parser.fetchChapterImages(task.chapterUrl);
    
    if (imageUrls.isEmpty) return;

    final appDir = await getApplicationDocumentsDirectory();
    final safeMangaTitle = task.mangaTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final safeChapterTitle = task.chapterTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    
    final dirPath = '${appDir.path}/downloads/${task.sourceId}/$safeMangaTitle/$safeChapterTitle';
    final directory = Directory(dirPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    int successCount = 0;
    const int concurrency = 5;
    
    for (int i = 0; i < imageUrls.length; i += concurrency) {
      final chunk = imageUrls.sublist(i, i + concurrency > imageUrls.length ? imageUrls.length : i + concurrency);
      final indexOffset = i;

      final results = await Future.wait(chunk.asMap().entries.map((entry) async {
        final imgUrl = entry.value;
        final imgIndex = indexOffset + entry.key;
        return _downloadImage(imgUrl, dirPath, imgIndex, parser.baseUrl);
      }));
      
      successCount += results.where((r) => r).length;
    }

    if (successCount > 0) {
      await DownloadDB.saveDownload(DownloadedChapter(
        chapterUrl: task.chapterUrl,
        chapterTitle: task.chapterTitle,
        mangaTitle: task.mangaTitle,
        mangaUrl: task.mangaUrl,
        directoryPath: dirPath,
        imageCount: successCount,
      ));
    } else {
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }

  static Future<bool> _downloadImage(String url, String dirPath, int index, String referer) async {
    int retries = 3;
    while (retries > 0) {
      try {
        final res = await _client.get(
          Uri.parse(url),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Referer': referer,
          }
        ).timeout(const Duration(seconds: 30));

        if (res.statusCode == 200) {
          final file = File('$dirPath/${index.toString().padLeft(4, '0')}.jpg');
          await file.writeAsBytes(res.bodyBytes);
          return true;
        }
      } catch (e) {
        print('Retry $retries for $url: $e');
      }
      retries--;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  static Future<void> deleteChapter(String chapterUrl) async {
    final download = DownloadDB.getDownload(chapterUrl);
    if (download != null) {
      final directory = Directory(download.directoryPath);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      await DownloadDB.removeDownload(chapterUrl);
    }
  }
}
