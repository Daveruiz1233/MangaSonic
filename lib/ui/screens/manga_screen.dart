import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:manga_sonic/ui/screens/chapter_reader_screen.dart';
import 'package:manga_sonic/data/models/models.dart';
import 'package:manga_sonic/data/db/library_db.dart';
import 'package:manga_sonic/data/db/download_db.dart';
import 'package:manga_sonic/data/db/history_db.dart';
import 'package:manga_sonic/data/db/manga_cache_db.dart';
import 'package:manga_sonic/data/models/library_models.dart';
import 'package:manga_sonic/utils/parser_factory.dart';
import 'package:manga_sonic/utils/download_manager.dart';
import 'package:manga_sonic/utils/cloudflare_interceptor.dart';
import 'package:url_launcher/url_launcher.dart';

class MangaScreen extends StatefulWidget {
  final String mangaTitle;
  final String mangaUrl;
  final String coverUrl;
  final String sourceId;

  const MangaScreen({
    super.key,
    required this.mangaTitle,
    required this.mangaUrl,
    required this.coverUrl,
    required this.sourceId,
  });

  @override
  State<MangaScreen> createState() => _MangaScreenState();
}

class _MangaScreenState extends State<MangaScreen> {
  MangaDetails? _details;
  bool _isLoading = true;
  bool _isSaved = false;
  bool _isDescriptionExpanded = false;
  final ScrollController _scrollController = ScrollController();
  double _opacity = 0.0;
  Color? _dominantColor;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _isSaved = LibraryDB.isSaved(widget.mangaUrl);
    _fetchData();
    _scrollController.addListener(_onScroll);
    _extractPalette();
  }

  void _onScroll() {
    if (_scrollController.offset <= 200) {
      setState(() => _opacity = _scrollController.offset / 200);
    } else if (_opacity != 1.0) {
      setState(() => _opacity = 1.0);
    }
  }

  Future<void> _extractPalette() async {
    try {
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(widget.coverUrl),
        maximumColorCount: 20,
      );
      if (mounted) {
        setState(() {
          _dominantColor = paletteGenerator.dominantColor?.color;
        });
      }
    } catch (_) {
      // Fallback to default
    }
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _isOffline = false;
    });

    final cachedDetails = MangaCacheDB.getDetails(widget.mangaUrl);
    
    try {
      final parser = getParserForSite(widget.sourceId);
      final manga = Manga(
        title: widget.mangaTitle,
        url: widget.mangaUrl,
        coverUrl: widget.coverUrl,
        sourceId: widget.sourceId,
      );
      final details = await parser.fetchMangaDetails(manga);
      
      // Save to cache if successfully fetched
      await MangaCacheDB.saveDetails(widget.mangaUrl, details);

      if (mounted) {
        setState(() {
          _details = details;
          _isLoading = false;
          _isOffline = false;
        });
      }
    } catch (e) {
      debugPrint('Fetch error: $e');
      
      // If fetch fails, try to use cache
      if (cachedDetails != null) {
        if (mounted) {
          setState(() {
            _details = cachedDetails;
            _isLoading = false;
            _isOffline = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Working offline. Showing cached details.'))
          );
        }
        return;
      }

      if (e.toString().contains('403') || e.toString().contains('Cloudflare')) {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Passing Cloudflare... Please wait.'))
           );
        }
        await CloudflareInterceptor.bypass(widget.mangaUrl);
        return _fetchData();
      }
      
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  int _findContinueChapterIndex() {
    final chapters = _details?.chapters ?? [];
    if (chapters.isEmpty) return 0;
    // Find the first unread chapter starting from the oldest (bottom of latest-first list)
    for (int i = chapters.length - 1; i >= 0; i--) {
      if (!HistoryDB.isRead(chapters[i].url)) {
        return i;
      }
    }
    return 0; // Default to latest if all are read
  }

  void _navigateToChapter(int index, {int initialPage = 0, double initialOffset = 0.0}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChapterReaderScreen(
          allChapters: _details!.chapters,
          initialIndex: index,
          initialPage: initialPage,
          initialOffset: initialOffset,
          sourceId: widget.sourceId,
        ),
      ),
    ).then((_) => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_details == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Failed to load manga details.')),
      );
    }

    final chapters = _details!.chapters;
    final hasStartedReading = chapters.any((ch) => HistoryDB.isRead(ch.url) || HistoryDB.getLastPage(ch.url) > 0);
    final continueIndex = _findContinueChapterIndex();
    final continueChapter = chapters[continueIndex];
    final lastPage = HistoryDB.getLastPage(continueChapter.url);
    final lastOffset = HistoryDB.getLastPageOffset(continueChapter.url);
    
    final buttonText = !hasStartedReading 
        ? 'START READING' 
        : 'CONTINUE CHAPTER ${continueChapter.title.replaceAll(RegExp(r'[^0-9.]'), '')}${lastPage > 0 ? ' (Page ${lastPage + 1})' : ''}';

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: AnimatedOpacity(
          opacity: _opacity,
          duration: const Duration(milliseconds: 200),
          child: Text(widget.mangaTitle),
        ),
        actions: [
          IconButton(
            icon: Icon(_isSaved ? Icons.bookmark : Icons.bookmark_add_outlined),
            onPressed: _toggleSave,
          ),
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            onPressed: () => launchUrl(Uri.parse(widget.mangaUrl)),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.download_for_offline),
            onSelected: (value) async {
               if (value == 'all') _downloadChapters(chapters);
               if (value == 'unread') _downloadChapters(chapters.where((c) => !HistoryDB.isRead(c.url)).toList());
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('Download all chapters')),
              const PopupMenuItem(value: 'unread', child: Text('Download all unread')),
            ],
          )
        ],
      ),
      body: Stack(
        children: [
          // Blurred background
          Positioned.fill(
            child: CachedNetworkImage(
              imageUrl: widget.coverUrl,
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      (_dominantColor ?? Colors.black).withValues(alpha: 0.4),
                      Colors.black.withValues(alpha: 0.9),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          // Main content
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 100, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Section
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Cover Image
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: widget.coverUrl,
                              width: 120,
                              height: 180,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.mangaTitle,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                _infoRow(Icons.person_outline, _details!.author),
                                _infoRow(Icons.brush_outlined, _details!.artist),
                                _infoRow(Icons.info_outline, _details!.status),
                                const SizedBox(height: 12),
                                // Genre Tags
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: _details!.genres.map((g) => _genreTag(g)).toList(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Description
                      GestureDetector(
                        onTap: () => setState(() => _isDescriptionExpanded = !_isDescriptionExpanded),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _details!.description,
                              maxLines: _isDescriptionExpanded ? null : 4,
                              overflow: _isDescriptionExpanded ? null : TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isDescriptionExpanded ? "Show Less" : "Show More",
                              style: TextStyle(color: _dominantColor ?? Colors.deepPurpleAccent, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Action Row (Mark all, Refresh, etc)
                      Row(
                        children: [
                          const Text(
                            'CHAPTERS',
                            style: TextStyle(letterSpacing: 1.5, fontWeight: FontWeight.bold, color: Colors.white54),
                          ),
                          if (_isOffline) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.orange.withValues(alpha: 0.5), width: 0.5),
                              ),
                              child: const Text(
                                'OFFLINE',
                                style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                          const Spacer(),
                          Text(
                            '${chapters.length} Chapters',
                            style: const TextStyle(color: Colors.white38),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              
              // Chapter List
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final chapter = chapters[index];
                    final isRead = HistoryDB.isRead(chapter.url);
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      title: Text(
                        chapter.title,
                        style: TextStyle(
                          color: isRead ? Colors.white38 : Colors.white,
                          fontSize: 15,
                        ),
                      ),
                      trailing: DownloadDB.isDownloaded(chapter.url) 
                          ? const Icon(Icons.check_circle, color: Colors.green, size: 18)
                          : IconButton(
                              icon: const Icon(Icons.download, size: 18, color: Colors.white38),
                              onPressed: () => _downloadChapters([chapter]),
                            ),
                      onTap: () => _navigateToChapter(index, initialPage: 0),
                      onLongPress: () => _showChapterMenu(chapter, index),
                    );
                  },
                  childCount: chapters.length,
                ),
              ),
              
              // Suggestions
              if (_details!.suggestions.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      'YOU MIGHT ALSO LIKE',
                      style: TextStyle(letterSpacing: 1.5, fontWeight: FontWeight.bold, color: Colors.white54),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 200,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _details!.suggestions.length,
                      itemBuilder: (context, index) {
                        final suggestion = _details!.suggestions[index];
                        return _suggestionItem(suggestion);
                      },
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ]
            ],
          ),
          
          // Floating Start/Continue Button
          Positioned(
            bottom: 24,
            left: 24,
            right: 24,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: (_dominantColor ?? Colors.deepPurpleAccent).withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _dominantColor ?? Colors.deepPurpleAccent,
                  foregroundColor: ThemeData.estimateBrightnessForColor(_dominantColor ?? Colors.deepPurpleAccent) == Brightness.dark ? Colors.white : Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                ),
                onPressed: () => _navigateToChapter(continueIndex, initialPage: lastPage, initialOffset: lastOffset),
                child: Text(
                  buttonText,
                  style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white54),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _genreTag(String genre) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        genre,
        style: const TextStyle(color: Colors.white70, fontSize: 11),
      ),
    );
  }

  Widget _suggestionItem(Manga manga) {
    return GestureDetector(
      onTap: () {
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
        );
      },
      child: Container(
        width: 110,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: manga.coverUrl,
                width: 110,
                height: 150,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => Container(color: Colors.grey[900]),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              manga.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleSave() async {
    if (_isSaved) {
      await LibraryDB.removeItem(widget.mangaUrl);
      setState(() => _isSaved = false);
    } else {
      final categories = LibraryDB.getCategories();
      if (categories.isEmpty) {
         // Default backup if no categories
         final item = LibraryItem(
            mangaUrl: widget.mangaUrl,
            title: widget.mangaTitle,
            coverUrl: widget.coverUrl,
            sourceId: widget.sourceId,
            categoryId: 'default',
          );
          await LibraryDB.saveItem(item);
          setState(() => _isSaved = true);
          return;
      }
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
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                      if (mounted) {
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
  }

  Future<void> _downloadChapters(List<Chapter> chapters) async {
    if (chapters.isEmpty) return;
    
    // Bulk downloads: descending order to ascending (oldest to newest)
    final downloadList = chapters.length > 1 ? chapters.reversed.toList() : chapters;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Adding ${downloadList.length} chapters to downloads...'))
    );

    for (var chapter in downloadList) {
        try {
          // Note: DownloadManager will soon handle queueing internally
          await DownloadManager().downloadChapter(
            chapterUrl: chapter.url,
            chapterTitle: chapter.title,
            mangaTitle: widget.mangaTitle,
            mangaUrl: widget.mangaUrl,
            coverUrl: widget.coverUrl,
            author: _details?.author ?? 'Unknown',
            genres: _details?.genres ?? [],
            sourceId: widget.sourceId,
          );
          if (mounted) setState(() {});
        } catch (e) {
          debugPrint('Error downloading ${chapter.title}: $e');
        }
    }
    
    if (mounted) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Batch download task complete.'))
       );
    }
  }

  void _showChapterMenu(Chapter chapter, int index) {
      final chapters = _details?.chapters ?? [];
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
                    if (context.mounted) Navigator.pop(context);
                    if (mounted) setState(() {});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.visibility_off),
                  title: const Text('Mark as Unread'),
                  onTap: () async {
                    await HistoryDB.markAsRead(chapter.url, isRead: false);
                    if (context.mounted) Navigator.pop(context);
                    if (mounted) setState(() {});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.vertical_align_bottom),
                  title: const Text('Mark all previous as Read'),
                  onTap: () async {
                    for (int i = index; i < chapters.length; i++) {
                       await HistoryDB.markAsRead(chapters[i].url, isRead: true);
                    }
                    if (context.mounted) Navigator.pop(context);
                    if (mounted) setState(() {});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.vertical_align_top),
                  title: const Text('Mark all previous as Unread'),
                  onTap: () async {
                    for (int i = index; i < chapters.length; i++) {
                       await HistoryDB.markAsRead(chapters[i].url, isRead: false);
                    }
                    if (context.mounted) Navigator.pop(context);
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
          );
        }
      );
  }
}

