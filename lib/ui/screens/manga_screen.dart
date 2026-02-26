import 'package:flutter/material.dart';
import 'package:manga_sonic/ui/screens/chapter_reader_screen.dart';
import 'package:manga_sonic/data/models/models.dart';
import 'package:manga_sonic/data/db/library_db.dart';
import 'package:manga_sonic/data/db/download_db.dart';
import 'package:manga_sonic/data/db/history_db.dart';
import 'package:manga_sonic/data/models/library_models.dart';
import 'package:manga_sonic/utils/parser_factory.dart';
import 'package:manga_sonic/utils/download_manager.dart';
import 'package:manga_sonic/utils/cloudflare_interceptor.dart';

class MangaScreen extends StatefulWidget {
  final String mangaTitle;
  final String mangaUrl;
  final String coverUrl;
  final String sourceId;

  const MangaScreen({
    Key? key,
    required this.mangaTitle,
    required this.mangaUrl,
    required this.coverUrl,
    required this.sourceId,
  }) : super(key: key);

  @override
  State<MangaScreen> createState() => _MangaScreenState();
}

class _MangaScreenState extends State<MangaScreen> {
  bool _isLoading = true;
  List<Chapter> _chapters = [];
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    _isSaved = LibraryDB.isSaved(widget.mangaUrl);
    _fetchChapters();
  }

  Future<void> _fetchChapters() async {
    setState(() => _isLoading = true);
    try {
      final parser = getParserForSite(widget.sourceId);
      final list = await parser.fetchChapters(widget.mangaUrl);
      setState(() {
        _chapters = list;
        _isLoading = false;
      });
    } catch (e) {
      if (e.toString().contains('403') || e.toString().contains('Cloudflare')) {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Passing Cloudflare... Please wait.'))
           );
        }
        await CloudflareInterceptor.bypass(widget.mangaUrl);
        // Retry
        return _fetchChapters();
      }
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.mangaTitle),
        actions: [
          IconButton(
            icon: Icon(_isSaved ? Icons.bookmark : Icons.bookmark_add_outlined),
            onPressed: () async {
              if (_isSaved) {
                await LibraryDB.removeItem(widget.mangaUrl);
                setState(() => _isSaved = false);
              } else {
                final categories = LibraryDB.getCategories();
                showDialog(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: const Text('Add to Category'),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: categories.length,
                          itemBuilder: (context, index) {
                            final cat = categories[index];
                            return ListTile(
                              title: Text(cat.name),
                              onTap: () async {
                                final item = LibraryItem(
                                  mangaUrl: widget.mangaUrl,
                                  title: widget.mangaTitle,
                                  coverUrl: widget.coverUrl,
                                  sourceId: widget.sourceId,
                                  categoryId: cat.id,
                                );
                                await LibraryDB.saveItem(item);
                                if (mounted) {
                                  Navigator.pop(context);
                                  setState(() => _isSaved = true);
                                }
                              }
                            );
                          }
                        )
                      )
                    );
                  }
                );
              }
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.download_for_offline),
            onSelected: (value) async {
               if (value == 'all') _downloadChapters(_chapters);
               if (value == 'unread') _downloadChapters(_chapters.where((c) => !HistoryDB.isRead(c.url)).toList());
               if (value == 'read') _downloadChapters(_chapters.where((c) => HistoryDB.isRead(c.url)).toList());
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('Download all chapters')),
              const PopupMenuItem(value: 'unread', child: Text('Download all unread')),
              const PopupMenuItem(value: 'read', child: Text('Download all read')),
            ],
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _chapters.length,
              itemBuilder: (context, index) {
                final chapter = _chapters[index];
                final isRead = HistoryDB.isRead(chapter.url);
                return ListTile(
                  leading: Icon(
                    isRead ? Icons.visibility : Icons.visibility_off_outlined,
                    color: isRead ? Colors.grey : Colors.deepPurpleAccent,
                    size: 20,
                  ),
                  title: Text(
                    chapter.title,
                    style: TextStyle(
                      color: isRead ? Colors.grey : Colors.white,
                    ),
                  ),
                  trailing: DownloadDB.isDownloaded(chapter.url) 
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : IconButton(
                          icon: const Icon(Icons.download),
                          onPressed: () => _downloadChapters([chapter]),
                        ),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChapterReaderScreen(
                          allChapters: _chapters,
                          initialIndex: index,
                          sourceId: widget.sourceId,
                        ),
                      ),
                    );
                    if (mounted) setState(() {}); // refresh after reading
                  },
                  onLongPress: () {
                     _showChapterMenu(chapter, index);
                  },
                );
              },
            ),
    );
  }

  Future<void> _downloadChapters(List<Chapter> chapters) async {
    if (chapters.isEmpty) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Adding ${chapters.length} chapters to downloads...'))
    );

    for (var chapter in chapters) {
        try {
          // Note: DownloadManager will soon handle queueing internally
          await DownloadManager.downloadChapter(
            chapterUrl: chapter.url,
            chapterTitle: chapter.title,
            mangaTitle: widget.mangaTitle,
            mangaUrl: widget.mangaUrl,
            sourceId: widget.sourceId,
          );
          if (mounted) setState(() {});
        } catch (e) {
          print('Error downloading ${chapter.title}: $e');
        }
    }
    
    if (mounted) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Batch download task complete.'))
       );
    }
  }

  void _showChapterMenu(Chapter chapter, int index) {
      showModalBottomSheet(
        context: context,
        builder: (context) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.visibility),
                  title: const Text('Mark as Read'),
                  onTap: () async {
                    await HistoryDB.markAsRead(chapter.url, isRead: true);
                    Navigator.pop(context);
                    setState(() {});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.visibility_off),
                  title: const Text('Mark as Unread'),
                  onTap: () async {
                    await HistoryDB.markAsRead(chapter.url, isRead: false);
                    Navigator.pop(context);
                    setState(() {});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.vertical_align_bottom),
                  title: const Text('Mark all previous as Read'),
                  onTap: () async {
                    // Assuming list is latest-first (Asura/ManhuaTop order)
                    // Previous chapters are from index+1 to end
                    for (int i = index; i < _chapters.length; i++) {
                       await HistoryDB.markAsRead(_chapters[i].url, isRead: true);
                    }
                    Navigator.pop(context);
                    setState(() {});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.vertical_align_top),
                  title: const Text('Mark all previous as Unread'),
                  onTap: () async {
                    for (int i = index; i < _chapters.length; i++) {
                       await HistoryDB.markAsRead(_chapters[i].url, isRead: false);
                    }
                    Navigator.pop(context);
                    setState(() {});
                  },
                ),
              ],
            ),
          );
        }
      );
  }
}

