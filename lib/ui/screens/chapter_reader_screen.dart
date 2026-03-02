import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:manga_sonic/data/db/download_db.dart';
import 'package:manga_sonic/data/db/history_db.dart';
import 'package:manga_sonic/data/models/models.dart';
import 'package:manga_sonic/utils/parser_factory.dart';

class ChapterReaderScreen extends StatefulWidget {
  final List<Chapter> allChapters;
  final int initialIndex;
  final int initialPage;
  final double initialOffset;
  final String sourceId;

  const ChapterReaderScreen({
    super.key,
    required this.allChapters,
    required this.initialIndex,
    this.initialPage = 0,
    this.initialOffset = 0.0,
    required this.sourceId,
  });

  @override
  State<ChapterReaderScreen> createState() => _ChapterReaderScreenState();
}

class _ChapterReaderScreenState extends State<ChapterReaderScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = true;
  bool _showUI = true;
  
  // List of images correctly mapped to their chapter for reading progress
  final List<ReaderPage> _pages = [];
  final Map<int, GlobalKey> _pageKeys = {};
  int _currentChapterIndex = 0;
  bool _isFetchingNext = false;

  @override
  void initState() {
    super.initState();
    _currentChapterIndex = widget.initialIndex;
    _fetchChapter(widget.allChapters[_currentChapterIndex]);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_pages.isEmpty) return;
    
    // Exact Progress Tracking:
    // We find which page is currently most visible in the viewport
    int currentActiveIndex = -1;
    double minTopDistance = double.infinity;

    for (int i = 0; i < _pages.length; i++) {
      final key = _pageKeys[i];
      if (key == null) continue;
      final context = key.currentContext;
      if (context == null) continue;

      final box = context.findRenderObject() as RenderBox;
      final position = box.localToGlobal(Offset.zero, ancestor: context.findAncestorRenderObjectOfType<RenderObject>());
      final top = position.dy;

      // The active page is the one whose top is closest to the top of the viewport (0)
      // or covers the top of the viewport.
      if (top.abs() < minTopDistance) {
        minTopDistance = top.abs();
        currentActiveIndex = i;
      }
    }

    if (currentActiveIndex != -1) {
      final currentPage = _pages[currentActiveIndex];
      
      // Calculate offset within this page
      final key = _pageKeys[currentActiveIndex]!;
      final box = key.currentContext!.findRenderObject() as RenderBox;
      final position = box.localToGlobal(Offset.zero);
      final offsetWithinPage = position.dy.abs();

      // Find relative page index within its own chapter
      int pageIndexInChapter = 0;
      for (int i = currentActiveIndex - 1; i >= 0; i--) {
        if (_pages[i].chapterUrl == currentPage.chapterUrl) {
          pageIndexInChapter++;
        } else {
          break;
        }
      }
      
      HistoryDB.saveProgress(currentPage.chapterUrl, pageIndexInChapter, lastPageOffset: offsetWithinPage);
    }

    // Auto-mark as read logic: if we are near the end of the total scrollable area
    if (_scrollController.position.pixels > _scrollController.position.maxScrollExtent - 200) {
       final lastChapterUrl = _pages.last.chapterUrl;
       if (!HistoryDB.isRead(lastChapterUrl)) {
          HistoryDB.markAsRead(lastChapterUrl, isRead: true);
       }
    }

    // Load next chapter logic
    if (_scrollController.position.pixels > _scrollController.position.maxScrollExtent - 2000) {
      if (!_isFetchingNext && _currentChapterIndex > 0) {
         _loadNextChapter();
      }
    }
  }

  Future<void> _fetchChapter(Chapter chapter) async {
    setState(() => _isFetchingNext = true);
    try {
      List<ReaderPage> newPages = [];
      if (DownloadDB.isDownloaded(chapter.url)) {
        final download = DownloadDB.getDownload(chapter.url);
        if (download != null) {
          final dir = Directory(download.directoryPath);
          if (await dir.exists()) {
            final files = dir.listSync().whereType<File>().toList();
            files.sort((a, b) => a.path.compareTo(b.path));
            newPages = files.map((f) => ReaderPage(
                chapterUrl: chapter.url,
                chapterTitle: chapter.title,
                file: f,
              )).toList();
          }
        }
      }

      if (newPages.isEmpty) {
        final parser = getParserForSite(widget.sourceId);
        final list = await parser.fetchChapterImages(chapter.url);
        newPages = list.map((url) => ReaderPage(
          chapterUrl: chapter.url,
          chapterTitle: chapter.title,
          url: url,
        )).toList();
      }

      setState(() {
        _pages.addAll(newPages);
        _isLoading = false;
        _isFetchingNext = false;
      });

      // If this is the initial chapter and we have an initial page/offset, jump to it
      if (chapter.url == widget.allChapters[widget.initialIndex].url && (widget.initialPage > 0 || widget.initialOffset > 0)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _jumpToInitialPosition();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      setState(() {
         _isLoading = false;
         _isFetchingNext = false;
      });
    }
  }

  void _jumpToInitialPosition() {
    if (widget.initialPage <= 0 && widget.initialOffset <= 0) return;
    
    // Find the global index of the page within the total list of pages
    int globalPageIndex = widget.initialPage; // In simple case where one chapter loaded
    
    if (globalPageIndex >= _pages.length) return;

    final key = _pageKeys[globalPageIndex];
    if (key == null) return;
    final context = key.currentContext;
    if (context == null) return;

    final box = context.findRenderObject() as RenderBox;
    final viewport = RenderAbstractViewport.of(box);

    final RevealedOffset reveal = viewport.getOffsetToReveal(box, 0.0);
    double targetOffset = reveal.offset + widget.initialOffset;

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(targetOffset.clamp(0, _scrollController.position.maxScrollExtent));
    }
  }

  void _loadNextChapter() {
     _currentChapterIndex--; // Next chapter in a latest-first list
     _fetchChapter(widget.allChapters[_currentChapterIndex]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() => _showUI = !_showUI);
                  },
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.zero, // Remove any default padding
                    itemCount: _pages.length + (_isFetchingNext ? 1 : 0),
                    cacheExtent: 3000,
                    itemBuilder: (context, index) {
                      if (index == _pages.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      
                      final page = _pages[index];
                      final key = _pageKeys.putIfAbsent(index, () => GlobalKey());

                      Widget imageWidget;
                      if (page.file != null) {
                        imageWidget = Image.file(
                          page.file!,
                          fit: BoxFit.contain,
                          cacheWidth: 1200,
                          errorBuilder: (context, error, stackTrace) => _errorPlaceholder(),
                        );
                      } else {
                        imageWidget = CachedNetworkImage(
                          imageUrl: page.url!,
                          fit: BoxFit.contain,
                          memCacheWidth: 1200,
                          placeholder: (context, url) => _placeholder(index),
                          errorWidget: (context, url, error) => _errorPlaceholder(),
                        );
                      }

                      return Container(
                        key: key,
                        child: imageWidget,
                      );
                    },
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedOpacity(
                    opacity: _showUI ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !_showUI,
                      child: AppBar(
                        title: Text(_pages.isNotEmpty ? _pages.last.chapterTitle : widget.allChapters[widget.initialIndex].title),
                        backgroundColor: Colors.black.withValues(alpha: 0.7),
                        elevation: 0,
                        leading: IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                  ),
                ),

              ],
            ),
    );
  }

  Widget _placeholder(int index) {
    return Container(
      height: 400,
      color: Colors.grey[900],
      child: Center(
        child: Text(
          'Page ${index + 1}',
          style: const TextStyle(color: Colors.white54),
        ),
      ),
    );
  }

  Widget _errorPlaceholder() {
    return Container(
      height: 400,
      color: Colors.grey[900],
      child: const Center(child: Icon(Icons.broken_image, color: Colors.white)),
    );
  }
}

class ReaderPage {
  final String chapterUrl;
  final String chapterTitle;
  final String? url;
  final File? file;

  ReaderPage({required this.chapterUrl, required this.chapterTitle, this.url, this.file});
}
