import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:manga_sonic/data/db/download_db.dart';
import 'package:manga_sonic/data/models/models.dart';
import 'package:manga_sonic/ui/screens/chapter_reader_screen.dart';
import 'package:manga_sonic/utils/download_manager.dart';
import '../widgets/hero_card.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  bool _isSelecting = false;
  final Set<String> _selectedChapterUrls = {};

  void _enterSelectionMode(String chapterUrl) {
    setState(() {
      _isSelecting = true;
      _selectedChapterUrls.add(chapterUrl);
    });
  }

  void _toggleSelection(String chapterUrl) {
    setState(() {
      if (_selectedChapterUrls.contains(chapterUrl)) {
        _selectedChapterUrls.remove(chapterUrl);
        if (_selectedChapterUrls.isEmpty) _isSelecting = false;
      } else {
        _selectedChapterUrls.add(chapterUrl);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelecting = false;
      _selectedChapterUrls.clear();
    });
  }

  void _selectAll(List<_MangaDownloadGroup> groups) {
    setState(() {
      for (var group in groups) {
        for (var ch in group.completedChapters) {
          _selectedChapterUrls.add(ch.chapterUrl);
        }
      }
    });
  }

  Future<void> _deleteSelected(DownloadManager manager) async {
    final urls = List<String>.from(_selectedChapterUrls);
    _exitSelectionMode();
    for (var url in urls) {
      await manager.deleteChapter(url);
    }
  }

  double _extractChapterNumber(String title) {
    final numRegex = RegExp(r'(\d+(\.\d+)?)');
    final match = numRegex.firstMatch(title);
    return match != null ? double.tryParse(match.group(1)!) ?? 0 : 0;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DownloadManager>(
      builder: (context, manager, child) {
        final downloads = DownloadDB.getDownloads();
        final queue = manager.queue;
        final Map<String, _MangaDownloadGroup> groups = {};

        for (var d in downloads) {
          groups.putIfAbsent(d.mangaUrl, () => _MangaDownloadGroup(
            mangaTitle: d.mangaTitle, mangaUrl: d.mangaUrl, coverUrl: d.coverUrl,
            author: d.author, genres: d.genres,
          )).completedChapters.add(d);
        }
        for (var q in queue) {
          groups.putIfAbsent(q.mangaUrl, () => _MangaDownloadGroup(
            mangaTitle: q.mangaTitle, mangaUrl: q.mangaUrl, coverUrl: q.coverUrl,
            author: q.author, genres: q.genres,
          )).activeTasks.add(q);
        }

        for (var g in groups.values) {
          g.completedChapters.sort((a, b) => _extractChapterNumber(a.chapterTitle).compareTo(_extractChapterNumber(b.chapterTitle)));
          g.activeTasks.sort((a, b) => _extractChapterNumber(a.chapterTitle).compareTo(_extractChapterNumber(b.chapterTitle)));
        }

        final sortedGroups = groups.values.toList();

        return PopScope(
          canPop: !_isSelecting,
          onPopInvokedWithResult: (didPop, _) { if (!didPop && _isSelecting) _exitSelectionMode(); },
          child: Scaffold(
            appBar: AppBar(
              title: Text(_isSelecting ? '${_selectedChapterUrls.length} selected' : 'Download Manager'),
              actions: [
                if (_isSelecting) ...[
                  IconButton(icon: const Icon(Icons.select_all), onPressed: () => _selectAll(sortedGroups)),
                  IconButton(icon: const Icon(Icons.delete), onPressed: _selectedChapterUrls.isEmpty ? null : () => _showDeleteConfirmation(context, manager)),
                ] else if (queue.isNotEmpty) ...[
                  const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
                ],
              ],
            ),
            body: sortedGroups.isEmpty 
                ? const Center(child: Text('No downloads')) 
                : ListView.builder(
                    itemCount: sortedGroups.length,
                    itemBuilder: (context, index) {
                      final group = sortedGroups[index];
                      final dummyManga = Manga(
                        title: group.mangaTitle,
                        url: group.mangaUrl,
                        coverUrl: group.coverUrl,
                        sourceId: 'unknown',
                      );
                      
                      double progress = 1.0;
                      if (group.activeTasks.isNotEmpty) {
                        final activeP = group.activeTasks.fold(0.0, (sum, t) => sum + manager.getStatus(t.chapterUrl).progress) / group.activeTasks.length;
                        progress = (group.completedChapters.length + activeP) / (group.completedChapters.length + group.activeTasks.length);
                      }

                      final completed = group.completedChapters.map((c) => c.chapterTitle).toList();
                      final queued = group.activeTasks.map((c) => c.chapterTitle).toList();

                      final List<dynamic> allInGroup = [...group.completedChapters, ...group.activeTasks];
                      
                      return HeroCard(
                        manga: dummyManga,
                        description: group.author,
                        mode: HeroCardMode.downloading,
                        overallProgress: progress,
                        completedChapters: completed,
                        queuedChapters: queued,
                        selectedChapterTitles: _selectedChapterUrls
                            .map((url) {
                              final ch = allInGroup.firstWhere(
                                (c) => (c is DownloadedChapter ? c.chapterUrl : (c as DownloadTask).chapterUrl) == url,
                                orElse: () => null,
                              );
                              return ch?.chapterTitle ?? '';
                            })
                            .where((title) => title.isNotEmpty)
                            .toSet()
                            .cast<String>(),
                        onChapterTap: (title) {
                          final ch = allInGroup.firstWhere((c) => c.chapterTitle == title);
                          final url = ch is DownloadedChapter ? ch.chapterUrl : (ch as DownloadTask).chapterUrl;
                          _toggleSelection(url);
                        },
                        onChapterLongPress: (title) {
                          final ch = allInGroup.firstWhere((c) => c.chapterTitle == title);
                          final url = ch is DownloadedChapter ? ch.chapterUrl : (ch as DownloadTask).chapterUrl;
                          if (!_isSelecting) _enterSelectionMode(url);
                        },
                        onCancel: () => manager.cancelMangaDownloads(group.mangaUrl),
                        onSelectAll: () => setState(() {
                          for (var ch in allInGroup) {
                            _selectedChapterUrls.add(ch is DownloadedChapter ? ch.chapterUrl : (ch as DownloadTask).chapterUrl);
                          }
                          _isSelecting = true;
                        }),
                        onUnselectAll: () => setState(() {
                          for (var ch in allInGroup) {
                            _selectedChapterUrls.remove(ch is DownloadedChapter ? ch.chapterUrl : (ch as DownloadTask).chapterUrl);
                          }
                          if (_selectedChapterUrls.isEmpty) _isSelecting = false;
                        }),
                        onTap: () {},
                      );
                    },
                  ),
          ),
        );
      },
    );
  }

  void _showDeleteConfirmation(BuildContext context, DownloadManager manager) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Downloads'),
        content: Text('Delete ${_selectedChapterUrls.length} selected chapters?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(
            onPressed: () { Navigator.pop(ctx); _deleteSelected(manager); },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }
}

class _MangaDownloadGroup {
  final String mangaTitle, mangaUrl, coverUrl, author;
  final List<String> genres;
  final List<DownloadedChapter> completedChapters = [];
  final List<DownloadTask> activeTasks = [];
  _MangaDownloadGroup({required this.mangaTitle, required this.mangaUrl, required this.coverUrl, required this.author, required this.genres});
}
