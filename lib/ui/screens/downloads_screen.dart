import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:manga_sonic/data/db/download_db.dart';
import 'package:manga_sonic/data/models/models.dart';
import 'package:manga_sonic/ui/screens/chapter_reader_screen.dart';
import 'package:manga_sonic/utils/download_manager.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer<DownloadManager>(
      builder: (context, manager, child) {
        final downloads = DownloadDB.getDownloads();
        final queue = manager.queue;
        
        // Group everything by Manga URL
        final Map<String, _MangaDownloadGroup> groups = {};

        // Process completed downloads
        for (var d in downloads) {
          groups.putIfAbsent(d.mangaUrl, () => _MangaDownloadGroup(
            mangaTitle: d.mangaTitle,
            mangaUrl: d.mangaUrl,
            coverUrl: d.coverUrl,
            author: d.author,
            genres: d.genres,
          )).completedChapters.add(d);
        }

        // Process active/queued downloads
        for (var q in queue) {
          groups.putIfAbsent(q.mangaUrl, () => _MangaDownloadGroup(
            mangaTitle: q.mangaTitle,
            mangaUrl: q.mangaUrl,
            coverUrl: q.coverUrl,
            author: q.author,
            genres: q.genres,
          )).activeTasks.add(q);
        }

        final sortedGroups = groups.values.toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Download Manager'),
            actions: [
              if (queue.isNotEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                  ),
                )
            ],
          ),
          body: sortedGroups.isEmpty
              ? const Center(child: Text('No active or completed downloads'))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: sortedGroups.length,
                  itemBuilder: (context, index) {
                    return _MangaGroupTile(group: sortedGroups[index], manager: manager);
                  },
                ),
        );
      },
    );
  }
}

class _MangaDownloadGroup {
  final String mangaTitle;
  final String mangaUrl;
  final String coverUrl;
  final String author;
  final List<String> genres;
  final List<DownloadedChapter> completedChapters = [];
  final List<DownloadTask> activeTasks = [];

  _MangaDownloadGroup({
    required this.mangaTitle,
    required this.mangaUrl,
    required this.coverUrl,
    required this.author,
    required this.genres,
  });

  double get overallProgress {
    if (activeTasks.isEmpty) return 1.0;
    // Simple heuristic: status of the first active task for this manga
    return 0.5; // Placeholder for more complex aggregation if needed
  }
}

class _MangaGroupTile extends StatefulWidget {
  final _MangaDownloadGroup group;
  final DownloadManager manager;

  const _MangaGroupTile({required this.group, required this.manager});

  @override
  State<_MangaGroupTile> createState() => _MangaGroupTileState();
}

class _MangaGroupTileState extends State<_MangaGroupTile> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = widget.group.activeTasks.isNotEmpty;
    
    // Calculate progress based on active tasks
    double progress = 1.0;
    if (isActive) {
      final activeSubtaskProgress = widget.group.activeTasks.fold(0.0, (sum, t) => sum + widget.manager.getStatus(t.chapterUrl).progress) / widget.group.activeTasks.length;
      final completedCount = widget.group.completedChapters.length;
      final totalCount = completedCount + widget.group.activeTasks.length;
      progress = (completedCount + activeSubtaskProgress) / totalCount;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cover Image
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CachedNetworkImage(
                    imageUrl: widget.group.coverUrl,
                    width: 80,
                    height: 110,
                    fit: BoxFit.cover,
                    errorWidget: (_, err, trace) => Container(color: Colors.grey[900], width: 80, height: 110),
                  ),
                ),
                const SizedBox(width: 12),
                // Metadata
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.group.mangaTitle,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.group.genres.join(', '),
                        style: TextStyle(color: theme.colorScheme.primary, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.group.author,
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      const Spacer(),
                      if (isActive) ...[
                        Row(
                          children: [
                            Expanded(
                              child: LinearProgressIndicator(
                                value: progress,
                                backgroundColor: Colors.white10,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${(progress * 100).toInt()}%',
                              style: const TextStyle(fontSize: 10, color: Colors.white70),
                            ),
                          ],
                        ),
                      ] else ...[
                        Text(
                          '${widget.group.completedChapters.length} CHAPTERS DOWNLOADED',
                          style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(_isExpanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: () => setState(() => _isExpanded = !_isExpanded),
                ),
              ],
            ),
          ),
          if (_isExpanded) ...[
            const Divider(height: 1),
            Container(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  // Completed chapters
                  ...widget.group.completedChapters.map((ch) => ListTile(
                    dense: true,
                    title: Text(ch.chapterTitle),
                    trailing: const Icon(Icons.check_circle, color: Colors.green, size: 18),
                    onTap: () => _openReader(context, ch),
                    onLongPress: () => widget.manager.deleteChapter(ch.chapterUrl),
                  )),
                  // Loading/Queued chapters
                  ...widget.group.activeTasks.map((task) {
                    final status = widget.manager.getStatus(task.chapterUrl);
                    return ListTile(
                      dense: true,
                      title: Text(task.chapterTitle),
                      subtitle: status.isDownloading ? Text('Downloading ${status.downloadedImages}/${status.totalImages}') : const Text('Queued'),
                      trailing: status.isDownloading 
                        ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(value: status.progress, strokeWidth: 2))
                        : const Icon(Icons.timer_outlined, size: 18, color: Colors.white54),
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openReader(BuildContext context, DownloadedChapter d) {
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
          sourceId: 'offline',
        ),
      ),
    );
  }
}
