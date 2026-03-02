import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:manga_sonic/data/db/download_db.dart';
import 'package:manga_sonic/utils/parser_factory.dart';

class DownloadTask {
  final String chapterUrl;
  final String chapterTitle;
  final String mangaTitle;
  final String mangaUrl;
  final String coverUrl;
  final String author;
  final List<String> genres;
  final String sourceId;

  DownloadTask({
    required this.chapterUrl,
    required this.chapterTitle,
    required this.mangaTitle,
    required this.mangaUrl,
    required this.coverUrl,
    required this.author,
    required this.genres,
    required this.sourceId,
  });
}

class DownloadStatus {
  final double progress;
  final bool isDownloading;
  final int downloadedImages;
  final int totalImages;

  DownloadStatus({
    this.progress = 0.0,
    this.isDownloading = false,
    this.downloadedImages = 0,
    this.totalImages = 0,
  });
}

class DownloadManager extends ChangeNotifier {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;
  DownloadManager._internal();

  final List<DownloadTask> _queue = [];
  bool _isProcessing = false;
  final http.Client _client = http.Client();

  // Progress tracking: chapterUrl -> DownloadStatus
  final Map<String, DownloadStatus> _statuses = {};

  List<DownloadTask> get queue => List.unmodifiable(_queue);
  Map<String, DownloadStatus> get statuses => Map.unmodifiable(_statuses);

  DownloadStatus getStatus(String chapterUrl) {
    if (_statuses.containsKey(chapterUrl)) {
      return _statuses[chapterUrl] ?? DownloadStatus();
    }
    // If not in statuses but in queue, it's pending/queued
    if (_queue.any((t) => t.chapterUrl == chapterUrl)) {
      return DownloadStatus(isDownloading: false, progress: 0.0);
    }
    // Default empty status
    return DownloadStatus();
  }

  Future<void> downloadChapter({
    required String chapterUrl,
    required String chapterTitle,
    required String mangaTitle,
    required String mangaUrl,
    required String coverUrl,
    required String author,
    required List<String> genres,
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
      coverUrl: coverUrl,
      author: author,
      genres: genres,
      sourceId: sourceId,
    ));

    // The task is now queued. Status will be picked up dynamically by `getStatus()`.
    notifyListeners();

    if (!_isProcessing) {
      _processQueue();
    }
  }

  Future<void> _processQueue() async {
    if (_queue.isEmpty) {
      _isProcessing = false;
      return;
    }

    _isProcessing = true;
    final task = _queue.first;

    try {
      await _executeTask(task);
    } catch (e) {
      debugPrint('Error processing task ${task.chapterTitle}: $e');
      _statuses.remove(task.chapterUrl);
      notifyListeners();
    }

    _queue.removeAt(0);
    _processQueue();
  }

  Future<void> _executeTask(DownloadTask task) async {
    final parser = getParserForSite(task.sourceId);
    final imageUrls = await parser.fetchChapterImages(task.chapterUrl);
    
    if (imageUrls.isEmpty) {
      _statuses.remove(task.chapterUrl);
      notifyListeners();
      return;
    }

    _statuses[task.chapterUrl] = DownloadStatus(
      isDownloading: true,
      totalImages: imageUrls.length,
      downloadedImages: 0,
      progress: 0.0,
    );
    notifyListeners();

    final appDir = await getApplicationDocumentsDirectory();
    final safeMangaTitle = task.mangaTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final safeChapterTitle = task.chapterTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    
    final dirPath = '${appDir.path}/downloads/${task.sourceId}/$safeMangaTitle/$safeChapterTitle';
    final directory = Directory(dirPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    int successCount = 0;
    const int concurrency = 3; // Reduced for better stability
    
    for (int i = 0; i < imageUrls.length; i += concurrency) {
      final end = (i + concurrency > imageUrls.length) ? imageUrls.length : i + concurrency;
      final chunk = imageUrls.sublist(i, end);
      final indexOffset = i;

      final results = await Future.wait(chunk.asMap().entries.map((entry) async {
        final imgUrl = entry.value;
        final imgIndex = indexOffset + entry.key;
        return _downloadImage(imgUrl, dirPath, imgIndex, parser.baseUrl);
      }));
      
      successCount += results.where((r) => r).length;
      
      // Update progress
      _statuses[task.chapterUrl] = DownloadStatus(
        isDownloading: true,
        totalImages: imageUrls.length,
        downloadedImages: successCount,
        progress: successCount / imageUrls.length,
      );
      notifyListeners();
    }

    if (successCount > 0) {
      await DownloadDB.saveDownload(DownloadedChapter(
        chapterUrl: task.chapterUrl,
        chapterTitle: task.chapterTitle,
        mangaTitle: task.mangaTitle,
        mangaUrl: task.mangaUrl,
        coverUrl: task.coverUrl,
        author: task.author,
        genres: task.genres,
        directoryPath: dirPath,
        imageCount: successCount,
      ));
    } else {
      if (await directory.exists()) await directory.delete(recursive: true);
    }

    _statuses.remove(task.chapterUrl);
    notifyListeners();
  }

  Future<bool> _downloadImage(String url, String dirPath, int index, String referer) async {
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
        debugPrint('Retry $retries for $url: $e');
      }
      retries--;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  Future<void> deleteChapter(String chapterUrl) async {
    final download = DownloadDB.getDownload(chapterUrl);
    if (download != null) {
      final directory = Directory(download.directoryPath);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      await DownloadDB.removeDownload(chapterUrl);
      notifyListeners();
    }
  }
}
