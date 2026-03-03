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
  bool _isFetchingPrev = false;
  DateTime _lastSaveTime = DateTime.now();

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
    
    // Throttled Progress Tracking & Mark-As-Read:
    if (DateTime.now().difference(_lastSaveTime) < const Duration(milliseconds: 200)) return;
    _lastSaveTime = DateTime.now();

    int firstVisibleIndex = -1;
    
    // We iterate through pages to find the first visible one and check for chapter boundaries
    for (int i = 0; i < _pages.length; i++) {
        final key = _pageKeys[i];
        if (key == null) continue;
        final context = key.currentContext;
        if (context == null) continue;

        final box = context.findRenderObject() as RenderBox;
        // Get position relative to the screen/scrollable area
        final position = box.localToGlobal(Offset.zero);
        final top = position.dy;
        final bottom = top + box.size.height;

        final currentPage = _pages[i];

        // 1. Precise Mark-As-Read:
        // Check if this is the last page of a chapter
        final isLastPageOfChapter = i == _pages.length - 1 || _pages[i+1].chapterUrl != currentPage.chapterUrl;
        
        if (isLastPageOfChapter && bottom < 0) {
            // The last page of this chapter has scrolled completely past the top
            if (!HistoryDB.isRead(currentPage.chapterUrl)) {
                HistoryDB.markAsRead(currentPage.chapterUrl, isRead: true);
                debugPrint('Marked as read: ${currentPage.chapterTitle}');
            }
        }

        // 2. Smart Progress Tracking:
        // The "active" page is the first one that is currently visible (bottom > 0)
        if (firstVisibleIndex == -1 && bottom > 10) { // Slight buffer
            firstVisibleIndex = i;
            
            // Calculate offset within this page (how much is scrolled past the top)
            final offsetWithinPage = top < 0 ? top.abs() : 0.0;

            // Find relative page index within its own chapter
            int pageIndexInChapter = 0;
            for (int k = i - 1; k >= 0; k--) {
                if (_pages[k].chapterUrl == currentPage.chapterUrl) {
                    pageIndexInChapter++;
                } else {
                    break;
                }
            }
            
            HistoryDB.saveProgress(currentPage.chapterUrl, pageIndexInChapter, lastPageOffset: offsetWithinPage);
        }
    }

    // Load previous chapter logic (Upward)
    if (_scrollController.position.pixels < 800) {
      if (!_isFetchingPrev && _currentChapterIndex < widget.allChapters.length - 1) {
         _loadPrevChapter();
      }
    }

    // Load next chapter logic (Downward)
    if (_scrollController.position.pixels > _scrollController.position.maxScrollExtent - 2000) {
      if (!_isFetchingNext && _currentChapterIndex > 0) {
         _loadNextChapter();
      }
    }
  }

  Future<void> _fetchChapter(Chapter chapter, {bool isPrepend = false}) async {
    if (isPrepend) {
      setState(() => _isFetchingPrev = true);
    } else {
      setState(() => _isFetchingNext = true);
    }
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
        try {
          final list = await parser.fetchChapterImages(chapter.url);
          newPages = list.map((url) => ReaderPage(
            chapterUrl: chapter.url,
            chapterTitle: chapter.title,
            url: url,
          )).toList();
        } catch (e) {
             debugPrint('Chapter fetch error: $e');
             if (mounted) {
               setState(() {
                 _isLoading = false;
                 _isFetchingNext = false;
               });
               showDialog(
                 context: context,
                 builder: (context) => AlertDialog(
                   title: const Text('Offline'),
                   content: const Text('This chapter has not been downloaded and cannot be viewed offline.'),
                   actions: [
                     TextButton(
                       onPressed: () => Navigator.pop(context),
                       child: const Text('OK'),
                     ),
                   ],
                 ),
               ).then((_) {
                 if (mounted && _pages.isEmpty) {
                   Navigator.pop(context);
                 }
               });
             }
             return;
        }
      }

      if (isPrepend) {
        // Shift existing keys forward
        final Map<int, GlobalKey> updatedKeys = {};
        _pageKeys.forEach((k, v) => updatedKeys[k + newPages.length] = v);
        _pageKeys.clear();
        _pageKeys.addAll(updatedKeys);

        // Record current height to adjust scroll
        double oldHeight = 0;
        if (_scrollController.hasClients) {
          oldHeight = _scrollController.position.maxScrollExtent;
        }

        _pages.insertAll(0, newPages);
        
        setState(() {
          _isFetchingPrev = false;
          _isLoading = false;
        });

        // Maintain scroll position after prepend
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            final newHeight = _scrollController.position.maxScrollExtent;
            final addedHeight = newHeight - oldHeight;
            _scrollController.jumpTo(_scrollController.offset + addedHeight);
          }
        });
      } else {
        setState(() {
          _pages.addAll(newPages);
          _isLoading = false;
          _isFetchingNext = false;
        });
      }

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
         _isFetchingPrev = false;
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

  void _loadPrevChapter() {
     _currentChapterIndex++; // Previous chapter in a latest-first list
     _fetchChapter(widget.allChapters[_currentChapterIndex], isPrepend: true);
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
                    padding: EdgeInsets.zero,
                    itemCount: _pages.length + (_isFetchingNext ? 1 : 0) + (_isFetchingPrev ? 1 : 0),
                    cacheExtent: 3000,
                    itemBuilder: (context, index) {
                      if (_isFetchingPrev && index == 0) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      
                      final actualIndex = _isFetchingPrev ? index - 1 : index;

                      if (actualIndex == _pages.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      
                      final page = _pages[actualIndex];
                      final key = _pageKeys.putIfAbsent(actualIndex, () => GlobalKey());

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
