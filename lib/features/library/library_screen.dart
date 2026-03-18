import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:manga_sonic/data/db/library_db.dart';
import 'package:manga_sonic/data/db/history_db.dart';
import 'package:manga_sonic/data/db/manga_cache_db.dart';
import 'package:manga_sonic/data/models/library_models.dart';
import 'package:manga_sonic/features/library/manga_screen.dart';
import 'package:manga_sonic/shared/widgets/hero_card.dart';
import 'package:manga_sonic/features/library/chapter_reader_screen.dart';
import 'package:manga_sonic/utils/library_update_service.dart';
import 'package:manga_sonic/utils/recently_read_resolver.dart';
import 'package:manga_sonic/shared/mixins/selection_mode_mixin.dart';
import 'package:manga_sonic/shared/widgets/manga_grid_card.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with SelectionModeMixin {
  late List<LibraryCategory> _categories;
  late List<LibraryItem> _items;
  String _selectedCategoryId = 'all';

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

  void _deleteSelected() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Selected?'),
        content: Text('Remove ${selectedIds.length} items from library?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              for (final id in selectedIds) {
                await LibraryDB.removeItem(id);
              }
              exitSelectionMode();
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

  @override
  Widget build(BuildContext context) {
    final searchQuery = _searchController.text.toLowerCase();

    final recentlyRead = RecentlyReadResolver.resolve(_items);
    final recentlyReadUrl = recentlyRead?.manga.url;

    final filteredItems = _items.where((i) {
      final matchesCategory =
          _selectedCategoryId == 'all' || i.categoryId == _selectedCategoryId;
      final matchesSearch = i.title.toLowerCase().contains(searchQuery);
      final isNotRecentlyRead = i.mangaUrl != recentlyReadUrl;
      return matchesCategory && matchesSearch && isNotRecentlyRead;
    }).toList();

    final List<LibraryItem> currentItems;
    if (_selectedCategoryId == 'all') {
      final seenUrls = <String>{};
      currentItems =
          filteredItems.where((item) => seenUrls.add(item.mangaUrl)).toList();
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
        title: isSelecting
            ? Text('${selectedIds.length} Selected')
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
        actions: isSelecting
            ? [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _deleteSelected,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: exitSelectionMode,
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
                      if (isSelecting) return;
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
                manga: recentlyRead.manga,
                lastChapter: recentlyRead.chapter,
                lastPage: recentlyRead.lastPage,
                description: recentlyRead.description,
                genres: recentlyRead.genres,
                onTap: () {
                  final manga = recentlyRead.manga;
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
                  final manga = recentlyRead.manga;
                  final details = MangaCacheDB.getDetails(manga.url);
                  if (details != null) {
                    final chapter = recentlyRead.chapter;
                    final index =
                        details.chapters.indexWhere((c) => c.url == chapter.url);
                    if (index != -1) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChapterReaderScreen(
                            allChapters: details.chapters,
                            initialIndex: index,
                            initialPage: recentlyRead.lastPage,
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
                  final isSelected = selectedIds.contains(item.mangaUrl);

                  return MangaGridCard(
                    title: item.title,
                    coverUrl: item.coverUrl,
                    isSelected: isSelected,
                    hasUpdate: LibraryUpdateService.hasUpdate(item.mangaUrl),
                    onTap: () {
                      if (isSelecting) {
                        toggleSelection(item.mangaUrl);
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
                    onLongPress: () => toggleSelection(item.mangaUrl),
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
