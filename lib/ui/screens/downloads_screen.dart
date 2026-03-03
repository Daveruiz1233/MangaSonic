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
  // Multi-select state
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
        if (_selectedChapterUrls.isEmpty) {
          _isSelecting = false;
        }
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

  void _selectAllInGroup(_MangaDownloadGroup group) {
    setState(() {
      for (var ch in group.completedChapters) {
        _selectedChapterUrls.add(ch.chapterUrl);
      }
    });
  }

  void _deselectAllInGroup(_MangaDownloadGroup group) {
    setState(() {
      for (var ch in group.completedChapters) {
        _selectedChapterUrls.remove(ch.chapterUrl);
      }
      if (_selectedChapterUrls.isEmpty) {
        _isSelecting = false;
      }
    });
  }

  void _deselectAll() {
    setState(() {
      _selectedChapterUrls.clear();
    });
  }

  Future<void> _deleteSelected(DownloadManager manager) async {
    final urls = List<String>.from(_selectedChapterUrls);
    _exitSelectionMode();
    for (var url in urls) {
      await manager.deleteChapter(url);
    }
  }

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

        // Count total selectable (completed) chapters
        final totalSelectable = sortedGroups.fold<int>(
          0, (sum, g) => sum + g.completedChapters.length);
        final allSelected = _selectedChapterUrls.length == totalSelectable && totalSelectable > 0;

        return PopScope(
          canPop: !_isSelecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _isSelecting) {
              _exitSelectionMode();
            }
          },
          child: Scaffold(
            appBar: _isSelecting
                ? AppBar(
                    leading: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _exitSelectionMode,
                    ),
                    title: Text('${_selectedChapterUrls.length} selected'),
                    actions: [
                      // Select All / Deselect All
                      IconButton(
                        icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
                        tooltip: allSelected ? 'Deselect All' : 'Select All',
                        onPressed: () {
                          if (allSelected) {
                            _deselectAll();
                          } else {
                            _selectAll(sortedGroups);
                          }
                        },
                      ),
                      // Delete selected
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Delete Selected',
                        onPressed: _selectedChapterUrls.isEmpty
                            ? null
                            : () => _showDeleteConfirmation(context, manager),
                      ),
                    ],
                  )
                : AppBar(
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
                      return _MangaGroupTile(
                        group: sortedGroups[index],
                        manager: manager,
                        isSelecting: _isSelecting,
                        selectedUrls: _selectedChapterUrls,
                        onLongPress: _enterSelectionMode,
                        onToggle: _toggleSelection,
                        onSelectAllInGroup: _selectAllInGroup,
                        onDeselectAllInGroup: _deselectAllInGroup,
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
        content: Text(
          'Delete ${_selectedChapterUrls.length} selected chapter${_selectedChapterUrls.length == 1 ? '' : 's'}? '
          'This will remove the downloaded files from your device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteSelected(manager);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
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
    return 0.5;
  }
}

class _MangaGroupTile extends StatefulWidget {
  final _MangaDownloadGroup group;
  final DownloadManager manager;
  final bool isSelecting;
  final Set<String> selectedUrls;
  final void Function(String chapterUrl) onLongPress;
  final void Function(String chapterUrl) onToggle;
  final void Function(_MangaDownloadGroup group) onSelectAllInGroup;
  final void Function(_MangaDownloadGroup group) onDeselectAllInGroup;

  const _MangaGroupTile({
    required this.group,
    required this.manager,
    required this.isSelecting,
    required this.selectedUrls,
    required this.onLongPress,
    required this.onToggle,
    required this.onSelectAllInGroup,
    required this.onDeselectAllInGroup,
  });

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

    // Count how many of this group's chapters are selected
    final selectedInGroup = widget.group.completedChapters
        .where((ch) => widget.selectedUrls.contains(ch.chapterUrl))
        .length;
    final hasSelectedInGroup = selectedInGroup > 0;
    final allChaptersSelected = selectedInGroup == widget.group.completedChapters.length
        && widget.group.completedChapters.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      // Subtle highlight when some chapters in this group are selected
      color: hasSelectedInGroup ? theme.colorScheme.primary.withOpacity(0.08) : null,
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
                      const SizedBox(height: 8),
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
                      ] else if (widget.isSelecting && hasSelectedInGroup) ...[
                        Text(
                          '$selectedInGroup of ${widget.group.completedChapters.length} selected',
                          style: TextStyle(fontSize: 10, color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
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
            // Per-manga Select All / Deselect All row
            if (widget.isSelecting && widget.group.completedChapters.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Row(
                  children: [
                    Checkbox(
                      value: allChaptersSelected,
                      tristate: true,
                      onChanged: (_) {
                        if (allChaptersSelected) {
                          widget.onDeselectAllInGroup(widget.group);
                        } else {
                          widget.onSelectAllInGroup(widget.group);
                        }
                      },
                      activeColor: theme.colorScheme.primary,
                    ),
                    Text(
                      allChaptersSelected ? 'Deselect All' : 'Select All',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  // Completed chapters
                  ...widget.group.completedChapters.map((ch) {
                    final isSelected = widget.selectedUrls.contains(ch.chapterUrl);
                    return ListTile(
                      dense: true,
                      // Show checkbox when in selection mode
                      leading: widget.isSelecting
                          ? Checkbox(
                              value: isSelected,
                              onChanged: (_) => widget.onToggle(ch.chapterUrl),
                              activeColor: theme.colorScheme.primary,
                            )
                          : null,
                      title: Text(ch.chapterTitle),
                      trailing: widget.isSelecting
                          ? null
                          : const Icon(Icons.check_circle, color: Colors.green, size: 18),
                      selected: isSelected,
                      selectedTileColor: theme.colorScheme.primary.withOpacity(0.12),
                      onTap: widget.isSelecting
                          ? () => widget.onToggle(ch.chapterUrl)
                          : () => _openReader(context, ch),
                      onLongPress: widget.isSelecting
                          ? null
                          : () => widget.onLongPress(ch.chapterUrl),
                    );
                  }),
                  // Loading/Queued chapters (not selectable)
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
