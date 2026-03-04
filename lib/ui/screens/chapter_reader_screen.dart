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

  final Map<int, double> _itemHeights = {};

  void _onItemSizeChanged(int index, Size size) {
    if (!mounted || !_scrollController.hasClients) return;

    final double oldHeight = _itemHeights[index] ?? 400.0;
    final double newHeight = size.height;

    if ((newHeight - oldHeight).abs() > 0.5) {
      _itemHeights[index] = newHeight;

      if (index < _anchorVisibleIndex) {
        final diff = newHeight - oldHeight;
        double target = _scrollController.offset + diff;
        if (target < 0) target = 0;
        _scrollController.removeListener(_onScroll);
        _scrollController.jumpTo(target);
        _scrollController.addListener(_onScroll);
      }
    }
  }

  // List of images correctly mapped to their chapter for reading progress
  final List<ReaderPage> _pages = [];
  final Map<int, GlobalKey> _pageKeys = {};
  int _topChapterIndex = 0;
  int _bottomChapterIndex = 0;
  int _anchorVisibleIndex = 0;
  bool _isFetchingNext = false;
  bool _isFetchingPrev = false;
  DateTime _lastSaveTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _topChapterIndex = widget.initialIndex;
    _bottomChapterIndex = widget.initialIndex;
    _fetchChapter(widget.allChapters[_topChapterIndex]);
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
    if (DateTime.now().difference(_lastSaveTime) <
        const Duration(milliseconds: 200))
      return;
    _lastSaveTime = DateTime.now();

    int firstVisibleIndex = -1;

    // We iterate through pages to find the first visible one and check for chapter boundaries
    for (int i = 0; i < _pages.length; i++) {
      final key = _pageKeys[i];
      if (key == null) continue;
      final context = key.currentContext;
      if (context == null) continue;

      final box = context.findRenderObject() as RenderBox;
      if (!box.hasSize) continue;
      // Get position relative to the screen/scrollable area
      final position = box.localToGlobal(Offset.zero);
      final top = position.dy;
      final bottom = top + box.size.height;

      final currentPage = _pages[i];

      // 1. Precise Mark-As-Read:
      // Check if this is the last page of a chapter
      final isLastPageOfChapter =
          i == _pages.length - 1 ||
          _pages[i + 1].chapterUrl != currentPage.chapterUrl;

      if (isLastPageOfChapter && bottom < 0) {
        // The last page of this chapter has scrolled completely past the top
        if (!HistoryDB.isRead(currentPage.chapterUrl)) {
          HistoryDB.markAsRead(currentPage.chapterUrl, isRead: true);
          debugPrint('Marked as read: ${currentPage.chapterTitle}');
        }
      }

      // 2. Smart Progress Tracking:
      // The "active" page is the first one that is currently visible (bottom > 0)
      if (firstVisibleIndex == -1 && bottom > 10) {
        // Slight buffer
        firstVisibleIndex = i;
        _anchorVisibleIndex = i;

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

        HistoryDB.saveProgress(
          currentPage.chapterUrl,
          pageIndexInChapter,
          lastPageOffset: offsetWithinPage,
        );
      }
    }

    // Load previous chapter logic (Upward)
    // Only load previous if we are actively scrolling up (negative delta) and have reached the top
    // Trigger much earlier (8000px instead of 1500px) for aggressive preloading
    if (_scrollController.position.pixels < 8000 &&
        _scrollController.position.userScrollDirection ==
            ScrollDirection.forward) {
      if (!_isFetchingPrev &&
          _topChapterIndex < widget.allChapters.length - 1) {
        _loadPrevChapter();
      }
    }

    // Load next chapter logic (Downward)
    // Only load next if we are actively scrolling down (positive delta) and have reached the bottom
    // Trigger much earlier (8000px instead of 2500px) for aggressive preloading
    if (_scrollController.position.pixels >
            _scrollController.position.maxScrollExtent - 8000 &&
        _scrollController.position.userScrollDirection ==
            ScrollDirection.reverse) {
      if (!_isFetchingNext && _bottomChapterIndex > 0) {
        _loadNextChapter();
      }
    }
  }

  // Prevent multiple rapid chapter loads by adding a flag/cooldown
  bool _cooldownActive = false;

  Future<void> _fetchChapter(
    Chapter chapter, {
    bool isPrepend = false,
    bool isBackgroundPrefetch = false,
  }) async {
    if (_cooldownActive && !isBackgroundPrefetch) return;

    if (isPrepend) {
      setState(() => _isFetchingPrev = true);
    } else {
      setState(() => _isFetchingNext = true);
    }

    // Add brief cooldown to prevent runaway scroll triggers
    _cooldownActive = true;
    Future.delayed(const Duration(seconds: 2), () => _cooldownActive = false);
    try {
      List<ReaderPage> newPages = [];
      bool isOffline = false;
      if (DownloadDB.isDownloaded(chapter.url)) {
        isOffline = true;
        final download = DownloadDB.getDownload(chapter.url);
        if (download != null) {
          final dir = Directory(download.directoryPath);
          if (await dir.exists()) {
            final files = dir.listSync().whereType<File>().toList();
            files.sort((a, b) => a.path.compareTo(b.path));
            newPages = files
                .map(
                  (f) => ReaderPage(
                    chapterUrl: chapter.url,
                    chapterTitle: chapter.title,
                    file: f,
                  ),
                )
                .toList();
          }
        }
      }

      if (newPages.isEmpty) {
        final parser = getParserForSite(widget.sourceId);
        try {
          final list = await parser.fetchChapterImages(chapter.url);
          newPages = list
              .map(
                (url) => ReaderPage(
                  chapterUrl: chapter.url,
                  chapterTitle: chapter.title,
                  url: url,
                ),
              )
              .toList();
        } catch (e) {
          debugPrint('Chapter fetch error: $e');
          if (mounted) {
            setState(() {
              _isLoading = false;
              _isFetchingNext = false;
              _isFetchingPrev =
                  false; // Also reset prev if an error occurs during prepend
            });
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Offline'),
                content: const Text(
                  'This chapter has not been downloaded and cannot be viewed offline.',
                ),
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

        // Shift item heights forward
        final Map<int, double> updatedHeights = {};
        _itemHeights.forEach((k, v) => updatedHeights[k + newPages.length] = v);
        _itemHeights.clear();
        for (int i = 0; i < newPages.length; i++) {
          updatedHeights[i] = 400.0;
        }
        _itemHeights.addAll(updatedHeights);

        double addedHeight = newPages.length * 400.0;
        _pages.insertAll(0, newPages);
        _anchorVisibleIndex += newPages.length;

        _scrollController.removeListener(_onScroll);

        setState(() {
          _isFetchingPrev = false;
          _isLoading = false;
        });

        // Jump synchronously to maintain exact visual offset
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.offset + addedHeight);
        }
        _scrollController.addListener(_onScroll);
      } else {
        setState(() {
          _pages.addAll(newPages);
          _isLoading = false;
          _isFetchingNext = false;
        });
      }

      // If this is the initial chapter and we have an initial page/offset, jump to it
      if (chapter.url == widget.allChapters[widget.initialIndex].url &&
          (widget.initialPage > 0 || widget.initialOffset > 0)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _jumpToInitialPosition();
        });
      }

      // Offline Aggressive Prefetching
      // If the current chapter was successfully loaded offline, silently prefetch the next and previous
      // offline chapters so they are instantly ready for memory cache rendering.
      if (isOffline && !isBackgroundPrefetch) {
        if (_topChapterIndex < widget.allChapters.length - 1) {
          final prevChap = widget.allChapters[_topChapterIndex + 1];
          if (DownloadDB.isDownloaded(prevChap.url)) {
            _loadPrevChapter(isBackgroundPrefetch: true);
          }
        }
        if (_bottomChapterIndex > 0) {
          final nextChap = widget.allChapters[_bottomChapterIndex - 1];
          if (DownloadDB.isDownloaded(nextChap.url)) {
            _loadNextChapter(isBackgroundPrefetch: true);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
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
    int globalPageIndex = -1;
    for (int i = 0; i < _pages.length; i++) {
      if (_pages[i].chapterUrl == widget.allChapters[widget.initialIndex].url) {
        globalPageIndex = i + widget.initialPage;
        break;
      }
    }

    // Fallback if not found (shouldn't happen)
    if (globalPageIndex == -1) {
      globalPageIndex = widget.initialPage;
    }

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
      _scrollController.jumpTo(
        targetOffset.clamp(0, _scrollController.position.maxScrollExtent),
      );
    }
  }

  void _loadNextChapter({bool isBackgroundPrefetch = false}) {
    _bottomChapterIndex--; // Next chapter in a latest-first list
    _fetchChapter(
      widget.allChapters[_bottomChapterIndex],
      isBackgroundPrefetch: isBackgroundPrefetch,
    );
  }

  void _loadPrevChapter({bool isBackgroundPrefetch = false}) {
    _topChapterIndex++; // Previous chapter in a latest-first list
    _fetchChapter(
      widget.allChapters[_topChapterIndex],
      isPrepend: true,
      isBackgroundPrefetch: isBackgroundPrefetch,
    );
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
                    itemCount: _pages.length,
                    cacheExtent:
                        15000, // Massive aggressive caching (approx 5-10 pages ahead/behind)
                    itemBuilder: (context, index) {
                      final page = _pages[index];
                      final key = _pageKeys.putIfAbsent(
                        index,
                        () => GlobalKey(),
                      );

                      Widget imageWidget;
                      if (page.file != null) {
                        imageWidget = Image.file(
                          page.file!,
                          fit: BoxFit.contain,
                          cacheWidth: 1200,
                          errorBuilder: (context, error, stackTrace) =>
                              _errorPlaceholder(),
                        );
                      } else {
                        imageWidget = CachedNetworkImage(
                          imageUrl: page.url!,
                          fit: BoxFit.contain,
                          memCacheWidth: 1200,
                          placeholder: (context, url) => _placeholder(index),
                          errorWidget: (context, url, error) =>
                              _errorPlaceholder(),
                        );
                      }

                      return Container(
                        key: key,
                        // Provide a minimum height so zero-height images don't collapse
                        // the scroll view and trigger runaway scrolling while decoding
                        constraints: const BoxConstraints(minHeight: 400),
                        child: SizeReportingWidget(
                          onSizeChanged: (size) =>
                              _onItemSizeChanged(index, size),
                          child: RepaintBoundary(child: imageWidget),
                        ),
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
                        title: Text(
                          _pages.isNotEmpty
                              ? _pages.last.chapterTitle
                              : widget.allChapters[widget.initialIndex].title,
                        ),
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
                if (_isFetchingPrev)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 20,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_isFetchingNext)
                  Positioned(
                    bottom: 40,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
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

class SizeReportingWidget extends StatefulWidget {
  final Widget child;
  final ValueChanged<Size> onSizeChanged;

  const SizeReportingWidget({
    super.key,
    required this.child,
    required this.onSizeChanged,
  });

  @override
  State<SizeReportingWidget> createState() => _SizeReportingWidgetState();
}

class _SizeReportingWidgetState extends State<SizeReportingWidget> {
  Size? _oldSize;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final size = context.size;
      if (size != null && size != _oldSize) {
        _oldSize = size;
        widget.onSizeChanged(size);
      }
    });
    return widget.child;
  }
}

class ReaderPage {
  final String chapterUrl;
  final String chapterTitle;
  final String? url;
  final File? file;

  ReaderPage({
    required this.chapterUrl,
    required this.chapterTitle,
    this.url,
    this.file,
  });
}
