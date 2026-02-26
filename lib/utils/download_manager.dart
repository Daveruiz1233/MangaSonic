import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:manga_sonic/data/db/download_db.dart';
import 'package:manga_sonic/utils/parser_factory.dart';

class DownloadManager {
  static Future<void> downloadChapter({
    required String chapterUrl,
    required String chapterTitle,
    required String mangaTitle,
    required String mangaUrl,
    required String sourceId,
  }) async {
    if (DownloadDB.isDownloaded(chapterUrl)) return; // Already downloaded

    final parser = getParserForSite(sourceId);
    final imageUrls = await parser.fetchChapterImages(chapterUrl);
    
    if (imageUrls.isEmpty) throw Exception('No images found to download.');

    final appDir = await getApplicationDocumentsDirectory();
    final safeMangaTitle = mangaTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final safeChapterTitle = chapterTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    
    final dirPath = '${appDir.path}/downloads/$sourceId/$safeMangaTitle/$safeChapterTitle';
    final directory = Directory(dirPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final client = http.Client();
    int successCount = 0;

    for (int i = 0; i < imageUrls.length; i++) {
        final url = imageUrls[i];
        try {
          final res = await client.get(
            Uri.parse(url),
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              'Referer': parser.baseUrl,
            }
          );
          if (res.statusCode == 200) {
            final file = File('$dirPath/${i.toString().padLeft(4, '0')}.jpg');
            await file.writeAsBytes(res.bodyBytes);
            successCount++;
          }
        } catch (e) {
          // You could retry here. For simplicity, we just print
          print('Error downloading $url: $e');
        }
    }
    client.close();

    if (successCount > 0) {
      await DownloadDB.saveDownload(DownloadedChapter(
        chapterUrl: chapterUrl,
        chapterTitle: chapterTitle,
        mangaTitle: mangaTitle,
        mangaUrl: mangaUrl,
        directoryPath: dirPath,
        imageCount: successCount,
      ));
    } else {
        // Clear directory if entirely failed
        await directory.delete(recursive: true);
        throw Exception('Failed to download any images');
    }
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
