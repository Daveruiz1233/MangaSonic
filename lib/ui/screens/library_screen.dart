import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:manga_sonic/data/db/library_db.dart';
import 'package:manga_sonic/data/models/library_models.dart';
import 'package:manga_sonic/ui/screens/manga_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late List<LibraryCategory> _categories;
  late List<LibraryItem> _items;
  String _selectedCategoryId = 'default';

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
      _categories = LibraryDB.getCategories();
      _items = LibraryDB.getItems();
      if (!_categories.any((c) => c.id == _selectedCategoryId) &&
          _categories.isNotEmpty) {
        _selectedCategoryId = _categories.first.id;
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

  @override
  Widget build(BuildContext context) {
    final searchQuery = _searchController.text.toLowerCase();
    final currentItems = _items.where((i) {
      final matchesCategory = i.categoryId == _selectedCategoryId;
      final matchesSearch = i.title.toLowerCase().contains(searchQuery);
      return matchesCategory && matchesSearch;
    }).toList();
    final theme = Theme.of(context);

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
                  IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () => setState(() => _isSearching = true),
                  ),
                IconButton(
                  icon: const Icon(Icons.filter_list),
                  onPressed: () {},
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'add_category') _addCategoryDialog();
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'add_category',
                      child: Text('Add Category'),
                    ),
                  ],
                ),
              ],
      ),
      body: Column(
        children: [
          SizedBox(
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
                        color: isSelected ? theme.primaryColor : Colors.white70,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8.0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.65,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: currentItems.length,
              itemBuilder: (context, index) {
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
                  child: Stack(
                    children: [
                      Card(
                        color: Colors.grey[900],
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: isSelected
                              ? BorderSide(color: theme.primaryColor, width: 3)
                              : BorderSide.none,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: CachedNetworkImage(
                                imageUrl: item.coverUrl,
                                fit: BoxFit.cover,
                                memCacheWidth: 300,
                                placeholder: (context, url) => Container(
                                  color: theme.primaryColor.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                                errorWidget: (context, url, error) =>
                                    const Icon(Icons.error),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Text(
                                item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: CircleAvatar(
                            radius: 12,
                            backgroundColor: theme.primaryColor,
                            child: const Icon(
                              Icons.check,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
