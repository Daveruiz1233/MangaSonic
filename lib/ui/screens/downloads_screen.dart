import 'package:flutter/material.dart';
import 'package:manga_sonic/data/db/download_db.dart';
import 'package:manga_sonic/data/models/models.dart';
import 'package:manga_sonic/ui/screens/chapter_reader_screen.dart';
import 'package:manga_sonic/utils/download_manager.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({Key? key}) : super(key: key);

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  late List<DownloadedChapter> _downloads;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    setState(() {
      _downloads = DownloadDB.getDownloads();
    });
  }

  Future<void> _deleteDownload(String url) async {
    await DownloadManager.deleteChapter(url);
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
      ),
      body: _downloads.isEmpty
          ? const Center(child: Text('No downloaded chapters'))
          : ListView.builder(
              itemCount: _downloads.length,
              itemBuilder: (context, index) {
                final d = _downloads[index];
                return ListTile(
                  title: Text(d.mangaTitle),
                  subtitle: Text('${d.chapterTitle} (${d.imageCount} pages)'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _deleteDownload(d.chapterUrl),
                  ),
                  onTap: () {
                    final chapter = Chapter(
                      title: d.chapterTitle,
                      url: d.chapterUrl,
                      mangaUrl: d.mangaUrl,
                    );
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChapterReaderScreen(
                          allChapters: [chapter],
                          initialIndex: 0,
                          sourceId: 'offline', // Won't be used for downloads
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
