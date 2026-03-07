import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:manga_sonic/data/db/library_db.dart';
import 'package:manga_sonic/data/db/history_db.dart';
import 'package:manga_sonic/data/db/manga_cache_db.dart';
import 'package:manga_sonic/data/models/models.dart';
import 'package:manga_sonic/data/models/library_models.dart';
import 'package:manga_sonic/ui/screens/manga_screen.dart';
import 'package:manga_sonic/ui/widgets/hero_card.dart';
import 'package:manga_sonic/ui/screens/chapter_reader_screen.dart';
import 'package:manga_sonic/utils/library_update_service.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late List<LibraryCategory> _categories;
  late List<LibraryItem> _items;
  String _selectedCategoryId = 'all';

  // Selection state
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};

  // Search state
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    setState(() {
      final dbCategories = LibraryDB.getCategories();
      _categories = [
        LibraryCategory(id: 'all', name: 'All'),
        ...dbCategories,
      ];
      _items = LibraryDB.getItems();
      
      if (!_categories.any((c) => c.id == _selectedCategoryId)) {
        _selectedCategoryId = 'all';
      }
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(id);
        _isSelectionMode = true;
      }
    });
  }

  void _deleteSelected() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Selected?'),
        content: Text('Remove ${_selectedIds.length} items from library?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              for (final id in _selectedIds) {
                await LibraryDB.removeItem(id);
              }
              _selectedIds.clear();
              _loadData();
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _addCategoryDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('New Category'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Category Name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  final id = DateTime.now().millisecondsSinceEpoch.toString();
                  await LibraryDB.addCategory(
                    LibraryCategory(id: id, name: name),
                  );
                  _loadData();
                }
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Map<String, dynamic>? _getRecentlyRead() {
    final statusBox = Hive.box('chapter_statuses');
    if (statusBox.isEmpty) return null;

    String? bestChapterUrl;
    int maxTimestamp = -1;
    ChapterStatus? bestStatus;

    // 1. Find the absolute latest read chapter
    for (var key in statusBox.keys) {
      final data = statusBox.get(key);
      if (data == null) continue;
      final status = ChapterStatus.fromMap(data);
      
      int ts = status.lastReadTimestamp ?? (status.isRead ? 1 : -1);
      
      if (ts > maxTimestamp) {
        maxTimestamp = ts;
        bestChapterUrl = key as String;
        bestStatus = status;
      }
    }

    if (bestChapterUrl == null || bestStatus == null) return null;

    // 2. Resolve Bibliographic Info
    LibraryItem? matchedItem;
    MangaDetails? matchedDetails;
    String? mangaUrl;

    for (final item in _items) {
      if (bestChapterUrl == item.mangaUrl || 
          bestChapterUrl.startsWith(item.mangaUrl) ||
          bestChapterUrl.contains(item.mangaUrl.replaceAll('manga/', ''))) {
        matchedItem = item;
        mangaUrl = item.mangaUrl;
        break;
      }
    }

    if (mangaUrl == null) {
      final cacheBox = Hive.box('manga_details_cache');
      for (var key in cacheBox.keys) {
        final detailsMap = cacheBox.get(key);
        if (detailsMap == null) continue;
        final details = MangaDetails.fromMap(detailsMap);
        if (details.chapters.any((c) => c.url == bestChapterUrl)) {
          matchedDetails = details;
          mangaUrl = key as String;
          break;
        }
      }
    }

    if (mangaUrl == null && matchedItem == null) return null;

    final title = matchedItem?.title ?? (matchedDetails != null ? matchedDetails.description.split('\n')[0] : 'Manga');
    final cover = matchedItem?.coverUrl ?? '';
    final source = matchedItem?.sourceId ?? 'unknown';

    final details = matchedDetails ?? MangaCacheDB.getDetails(mangaUrl!);
    final chapter = details?.chapters.firstWhere(
      (c) => c.url == bestChapterUrl,
      orElse: () => Chapter(
        title: 'Last Chapter',
        url: bestChapterUrl!,
        mangaUrl: mangaUrl ?? '',
      ),
    ) ?? Chapter(
        title: 'Last Chapter',
        url: bestChapterUrl!,
        mangaUrl: mangaUrl ?? '',
      );

    return {
      'manga': Manga(
        title: title,
        url: mangaUrl ?? '',
        coverUrl: cover,
        sourceId: source,
      ),
      'chapter': chapter,
      'page': bestStatus.lastPage,
      'description': details?.description ?? '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final searchQuery = _searchController.text.toLowerCase();
    
    final recentlyRead = _getRecentlyRead();
    final recentlyReadUrl = recentlyRead?['manga']?.url;

    final filteredItems = _items.where((i) {
      final matchesCategory = _selectedCategoryId == 'all' || i.categoryId == _selectedCategoryId;
      final matchesSearch = i.title.toLowerCase().contains(searchQuery);
      final isNotRecentlyRead = i.mangaUrl != recentlyReadUrl;
      return matchesCategory && matchesSearch && isNotRecentlyRead;
    }).toList();

    final List<LibraryItem> currentItems;
    if (_selectedCategoryId == 'all') {
      final seenUrls = <String>{};
      currentItems = filteredItems.where((item) => seenUrls.add(item.mangaUrl)).toList();
    } else {
      currentItems = filteredItems;
    }

    // Sort by date added (latest first)
    currentItems.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    final theme = Theme.of(context);
    context.watch<LibraryUpdateService>(); // Trigger rebuild on updates

    return Scaffold(
      appBar: AppBar(
        leading: _isSearching
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _isSearching = false;
                    _searchController.clear();
                  });
                },
              )
            : null,
        title: _isSelectionMode
            ? Text('${_selectedIds.length} Selected')
            : _isSearching
                ? TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search library...',
                      border: InputBorder.none,
                      hintStyle: TextStyle(color: Colors.white54),
                    ),
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                    onChanged: (_) => setState(() {}),
                  )
                : const Text(
                    'Library',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
        actions: _isSelectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _deleteSelected,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() {
                    _isSelectionMode = false;
                    _selectedIds.clear();
                  }),
                ),
              ]
            : [
                if (!_isSearching)
                  Consumer<LibraryUpdateService>(
                    builder: (context, updater, _) => updater.isUpdating
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.only(right: 16),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: () => updater.checkForUpdates(),
                          ),
                  ),
                IconButton(
                  icon: Icon(_isSearching ? Icons.close : Icons.search),
                  onPressed: () {
                    setState(() {
                      if (_isSearching) {
                        _isSearching = false;
                        _searchController.clear();
                      } else {
                        _isSearching = true;
                      }
                    });
                  },
                ),
                if (!_isSearching)
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: _addCategoryDialog,
                  ),
              ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: 50,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final isSelected = cat.id == _selectedCategoryId;
                  return GestureDetector(
                    onTap: () {
                      if (_isSelectionMode) return;
                      setState(() => _selectedCategoryId = cat.id);
                    },
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      margin: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? theme.primaryColor.withValues(alpha: 0.2)
                            : Colors.grey[850],
                        borderRadius: BorderRadius.circular(20),
                        border: isSelected
                            ? Border.all(color: theme.primaryColor, width: 1)
                            : Border.all(color: Colors.transparent, width: 1),
                      ),
                      child: Text(
                        cat.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color:
                              isSelected ? theme.primaryColor : Colors.white70,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          if (recentlyRead != null && !_isSearching)
            SliverToBoxAdapter(
              child: HeroCard(
                manga: recentlyRead['manga'],
                lastChapter: recentlyRead['chapter'],
                lastPage: recentlyRead['page'],
                description: recentlyRead['description'],
                onTap: () {
                  final manga = recentlyRead['manga'] as Manga;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MangaScreen(
                        mangaTitle: manga.title,
                        mangaUrl: manga.url,
                        coverUrl: manga.coverUrl,
                        sourceId: manga.sourceId,
                      ),
                    ),
                  ).then((_) => _loadData());
                },
                onContinue: () {
                  final manga = recentlyRead['manga'] as Manga;
                  final details = MangaCacheDB.getDetails(manga.url);
                  if (details != null) {
                    final chapter = recentlyRead['chapter'] as Chapter;
                    final index =
                        details.chapters.indexWhere((c) => c.url == chapter.url);
                    if (index != -1) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChapterReaderScreen(
                            allChapters: details.chapters,
                            initialIndex: index,
                            initialPage: recentlyRead['page'],
                            initialOffset: HistoryDB.getLastPageOffset(
                              chapter.url,
                            ),
                            sourceId: manga.sourceId,
                          ),
                        ),
                      ).then((_) => _loadData());
                    }
                  }
                },
              ),
            ),

          SliverPadding(
            padding: const EdgeInsets.all(8.0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.65,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = currentItems[index];
                  final isSelected = _selectedIds.contains(item.mangaUrl);

                  return GestureDetector(
                    onTap: () {
                      if (_isSelectionMode) {
                        _toggleSelection(item.mangaUrl);
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MangaScreen(
                              mangaTitle: item.title,
                              mangaUrl: item.mangaUrl,
                              coverUrl: item.coverUrl,
                              sourceId: item.sourceId,
                            ),
                          ),
                        ).then((value) => _loadData());
                      }
                    },
                    onLongPress: () => _toggleSelection(item.mangaUrl),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(
                              imageUrl: item.coverUrl,
                              fit: BoxFit.cover,
                              memCacheWidth: 300,
                              placeholder: (context, url) => Container(
                                color: theme.primaryColor.withValues(alpha: 0.1),
                              ),
                              errorWidget: (context, url, error) =>
                                  const Icon(Icons.error, color: Colors.white24),
                            ),
                            // Gradient Overlay
                            Positioned(
                              left: -5,
                              right: -5,
                              bottom: -5,
                              child: Container(
                                height: 75,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withValues(alpha: 0.8),
                                      Colors.black,
                                    ],
                                  ),
                                ),
                                padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
                                child: Text(
                                  item.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    height: 1.2,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black,
                                        blurRadius: 4,
                                        offset: Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (isSelected)
                              Positioned.fill(
                                child: Container(
                                  color: theme.primaryColor.withValues(alpha: 0.2),
                                  child: Center(
                                    child: CircleAvatar(
                                      radius: 18,
                                      backgroundColor: theme.primaryColor,
                                      child: const Icon(Icons.check, color: Colors.white, size: 24),
                                    ),
                                  ),
                                ),
                              ),
                            if (LibraryUpdateService.hasUpdate(item.mangaUrl))
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.primaryColor,
                                    borderRadius: BorderRadius.circular(4),
                                    boxShadow: const [
                                      BoxShadow(color: Colors.black45, blurRadius: 4),
                                    ],
                                  ),
                                  child: const Text(
                                    'NEW',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                childCount: currentItems.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],
      ),
    );
  }
}
