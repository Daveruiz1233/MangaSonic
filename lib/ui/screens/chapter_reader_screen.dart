import 'dart:async';
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
  late ScrollController _scrollController;
  final GlobalKey _centerKey = GlobalKey();

  // Forward pages = initial chapter + next chapters (scroll down)
  // Backward pages = previous chapters (scroll up)
  final List<ReaderPage> _forwardPages = [];
  final List<ReaderPage> _backwardPages = [];

  bool _isLoading = true;
  bool _showUI = true;
  bool _isFetchingNext = false;
  bool _isFetchingPrev = false;

  int _topChapterIndex = 0; // tracks upward (previous) chapter loading
  int _bottomChapterIndex = 0; // tracks downward (next) chapter loading

  // Progress tracking
  DateTime _lastSaveTime = DateTime.now();
  String _currentChapterTitle = '';
  int _currentPageInChapter = 0;
  int _currentChapterTotalPages = 0;

  // Track loaded chapter URLs to avoid duplicates
  final Set<String> _loadedChapterUrls = {};

  @override
  void initState() {
    super.initState();
    _topChapterIndex = widget.initialIndex;
    _bottomChapterIndex = widget.initialIndex;
    _currentChapterTitle = widget.allChapters[widget.initialIndex].title;

    // No initialScrollOffset needed — the target page will be placed at
    // the start of the forward sliver (offset 0) by _fetchInitialChapter.
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);

    _fetchInitialChapter();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // ─── SCROLL HANDLING ───────────────────────────────────────────────────

  void _onScroll() {
    if (_forwardPages.isEmpty && _backwardPages.isEmpty) return;

    _trackProgress();
    _checkLoadThresholds();
  }

  void _trackProgress() {
    // Throttle to 500ms
    final now = DateTime.now();
    if (now.difference(_lastSaveTime) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastSaveTime = now;

    bool foundVisible = false;

    // Check backward pages (furthest up → closest to center)
    // Backward sliver renders index 0 closest to center, last index furthest up.
    for (int i = _backwardPages.length - 1; i >= 0 && !foundVisible; i--) {
      final page = _backwardPages[i];
      if (page.isSeparator) continue;
      final ctx = page.key.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final pos = box.localToGlobal(Offset.zero);
      final top = pos.dy;
      final bottom = top + box.size.height;
      foundVisible = _processPageForTracking(
        page, top, bottom, isForward: false, localIndex: i,
      );
    }

    // Check forward pages
    for (int i = 0; i < _forwardPages.length && !foundVisible; i++) {
      final page = _forwardPages[i];
      if (page.isSeparator) continue;
      final ctx = page.key.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final pos = box.localToGlobal(Offset.zero);
      final top = pos.dy;
      final bottom = top + box.size.height;
      foundVisible = _processPageForTracking(
        page, top, bottom, isForward: true, localIndex: i,
      );
    }
  }

  /// Process a single page for progress tracking.
  /// Returns true if this was the first visible page (stop iteration).
  bool _processPageForTracking(
    ReaderPage page, double top, double bottom, {
    required bool isForward, required int localIndex,
  }) {
    // Mark-as-read: if last page of a chapter has scrolled fully off screen
    if (bottom < 0) {
      bool isLastOfChapter;
      if (isForward) {
        isLastOfChapter = localIndex == _forwardPages.length - 1 ||
            _forwardPages[localIndex + 1].chapterUrl != page.chapterUrl;
      } else {
        // Index 0 in backward = closest to center = last page visually
        isLastOfChapter = localIndex == 0 ||
            _backwardPages[localIndex - 1].chapterUrl != page.chapterUrl;
      }
      if (isLastOfChapter && !HistoryDB.isRead(page.chapterUrl)) {
        HistoryDB.markAsRead(page.chapterUrl, isRead: true);
      }
      return false; // keep looking
    }

    // First visible page
    if (bottom > 10) {
      final offsetWithinPage = top < 0 ? top.abs() : 0.0;

      // Calculate page index within its own chapter (skip separators).
      // Pages from the same chapter may be split across both slivers
      // (backward has pages before the restore point, forward has the rest).
      int pageIndexInChapter = 0;
      if (isForward) {
        // Count same-chapter pages before this one in the forward list
        for (int k = localIndex - 1; k >= 0; k--) {
          final p = _forwardPages[k];
          if (p.isSeparator) continue;
          if (p.chapterUrl == page.chapterUrl) {
            pageIndexInChapter++;
          } else {
            break;
          }
        }
        // If we reached the start of the forward list AND there are
        // backward pages from the same chapter, count those too.
        // (This happens when the initial chapter was split at the restore point.)
        if (localIndex == 0 ||
            (localIndex > 0 && _forwardPages[0].chapterUrl == page.chapterUrl)) {
          for (final p in _backwardPages) {
            if (p.isSeparator) continue;
            if (p.chapterUrl == page.chapterUrl) {
              pageIndexInChapter++;
            }
          }
        }
      } else {
        // Backward pages: higher index = earlier page in reading order
        for (int k = localIndex + 1; k < _backwardPages.length; k++) {
          final p = _backwardPages[k];
          if (p.isSeparator) continue;
          if (p.chapterUrl == page.chapterUrl) {
            pageIndexInChapter++;
          } else {
            break;
          }
        }
      }

      // Count total non-separator pages in this chapter
      int totalPages = 0;
      for (final p in _backwardPages) {
        if (!p.isSeparator && p.chapterUrl == page.chapterUrl) totalPages++;
      }
      for (final p in _forwardPages) {
        if (!p.isSeparator && p.chapterUrl == page.chapterUrl) totalPages++;
      }

      _currentChapterTitle = page.chapterTitle;
      _currentPageInChapter = pageIndexInChapter;
      _currentChapterTotalPages = totalPages;

      HistoryDB.saveProgress(
        page.chapterUrl,
        pageIndexInChapter,
        lastPageOffset: offsetWithinPage,
      );

      if (mounted) setState(() {});
      return true; // found first visible, stop
    }

    return false;
  }

  void _checkLoadThresholds() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;

    // Load previous chapter (scrolling up into negative extent)
    // minScrollExtent is negative for backward slivers
    if (pos.pixels < pos.minScrollExtent + 3000) {
      if (!_isFetchingPrev &&
          _topChapterIndex < widget.allChapters.length - 1) {
        _loadPrevChapter();
      }
    }

    // Load next chapter (scrolling down)
    if (pos.pixels > pos.maxScrollExtent - 3000) {
      if (!_isFetchingNext && _bottomChapterIndex > 0) {
        _loadNextChapter();
      }
    }
  }

  // ─── CHAPTER FETCHING ──────────────────────────────────────────────────

  Future<void> _fetchInitialChapter() async {
    final chapter = widget.allChapters[widget.initialIndex];
    final pages = await _fetchChapterPages(chapter);
    if (pages == null) return;

    _loadedChapterUrls.add(chapter.url);

    // Split pages at the target page index:
    // - Pages BEFORE the target go into the backward sliver (grow upward,
    //   their height changes can never affect the viewport position).
    // - Pages FROM the target onward go into the forward sliver (start
    //   at scroll offset 0, so the target page is immediately visible).
    final splitIndex = widget.initialPage.clamp(0, pages.length);

    // Pages before target go into backward sliver (reversed so index 0 = closest to center)
    if (splitIndex > 0) {
      final beforePages = pages.sublist(0, splitIndex);
      _backwardPages.addAll(beforePages.reversed);
    }

    // Pages from target onward go into forward sliver
    _forwardPages.addAll(pages.sublist(splitIndex));

    setState(() => _isLoading = false);

    // Apply sub-page offset (how far into the target page the user was)
    if (widget.initialOffset > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(widget.initialOffset.clamp(
            0.0, _scrollController.position.maxScrollExtent,
          ));
        }
      });
    }

    // Prefetch adjacent chapters in background
    _prefetchAdjacentChapters();
  }

  Future<List<ReaderPage>?> _fetchChapterPages(Chapter chapter) async {
    List<ReaderPage> pages = [];

    // Check downloaded/offline first
    if (DownloadDB.isDownloaded(chapter.url)) {
      final download = DownloadDB.getDownload(chapter.url);
      if (download != null) {
        final dir = Directory(download.directoryPath);
        if (await dir.exists()) {
          final files = dir.listSync().whereType<File>().toList();
          files.sort((a, b) => a.path.compareTo(b.path));
          pages = files
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

    // Fetch from network if no offline pages
    if (pages.isEmpty) {
      final parser = getParserForSite(widget.sourceId);
      try {
        final urls = await parser.fetchChapterImages(chapter.url);
        pages = urls
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
          _showOfflineDialog();
        }
        return null;
      }
    }

    // Warm the image cache for network images
    for (int i = 0; i < pages.length && i < 5; i++) {
      final url = pages[i].url;
      if (url != null) {
        _precacheImage(url);
      }
    }

    return pages;
  }

  void _precacheImage(String url) {
    try {
      // Trigger CachedNetworkImageProvider to start downloading
      CachedNetworkImageProvider(url).resolve(ImageConfiguration.empty);
    } catch (_) {}
  }

  void _showOfflineDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Offline'),
        content: const Text(
          'This chapter has not been downloaded and cannot be viewed offline.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    ).then((_) {
      if (mounted && _forwardPages.isEmpty && _backwardPages.isEmpty) {
        Navigator.pop(context);
      }
    });
  }

  void _loadNextChapter({bool isBackground = false}) {
    if (_isFetchingNext) return;
    final nextIndex = _bottomChapterIndex - 1; // latest-first list
    if (nextIndex < 0) return;
    final chapter = widget.allChapters[nextIndex];
    if (_loadedChapterUrls.contains(chapter.url)) return;

    _isFetchingNext = true;
    if (!isBackground && mounted) setState(() {});

    _fetchChapterPages(chapter).then((pages) {
      if (pages != null && pages.isNotEmpty && mounted) {
        _loadedChapterUrls.add(chapter.url);
        _bottomChapterIndex = nextIndex;

        // Add a chapter separator page before the new chapter
        final separator = ReaderPage(
          chapterUrl: chapter.url,
          chapterTitle: chapter.title,
          isSeparator: true,
        );

        setState(() {
          _forwardPages.add(separator);
          _forwardPages.addAll(pages);
          _isFetchingNext = false;
        });
      } else if (mounted) {
        setState(() => _isFetchingNext = false);
      }
    });
  }

  void _loadPrevChapter({bool isBackground = false}) {
    if (_isFetchingPrev) return;
    final prevIndex = _topChapterIndex + 1; // latest-first list
    if (prevIndex >= widget.allChapters.length) return;
    final chapter = widget.allChapters[prevIndex];
    if (_loadedChapterUrls.contains(chapter.url)) return;

    _isFetchingPrev = true;
    if (!isBackground && mounted) setState(() {});

    _fetchChapterPages(chapter).then((pages) {
      if (pages != null && pages.isNotEmpty && mounted) {
        _loadedChapterUrls.add(chapter.url);
        _topChapterIndex = prevIndex;

        // Add a chapter separator at the beginning (boundary between chapters)
        final separator = ReaderPage(
          chapterUrl: chapter.url,
          chapterTitle: chapter.title,
          isSeparator: true,
        );

        // Backward pages are rendered in reverse by the sliver, so:
        // index 0 = closest to center, last index = furthest up.
        // We want the new chapter pages to appear above existing backward pages.
        // New chapter's pages should be: page1, page2, ..., pageN, separator
        // Since sliver reverses: we insert at the END so they appear at the TOP.
        setState(() {
          _backwardPages.addAll(pages.reversed);
          _backwardPages.add(separator);
          _isFetchingPrev = false;
        });
      } else if (mounted) {
        setState(() => _isFetchingPrev = false);
      }
    });
  }

  void _prefetchAdjacentChapters() {
    // Prefetch next chapter data (not images, just page list)
    if (_bottomChapterIndex > 0) {
      final nextChapter = widget.allChapters[_bottomChapterIndex - 1];
      if (DownloadDB.isDownloaded(nextChapter.url)) {
        _loadNextChapter(isBackground: true);
      }
    }
    if (_topChapterIndex < widget.allChapters.length - 1) {
      final prevChapter = widget.allChapters[_topChapterIndex + 1];
      if (DownloadDB.isDownloaded(prevChapter.url)) {
        _loadPrevChapter(isBackground: true);
      }
    }
  }

  // Position restore is handled by splitting pages in _fetchInitialChapter:
  // pages before the target go into the backward sliver (can't affect viewport),
  // pages from the target onward go into the forward sliver (start at offset 0).
  // Only the sub-page offset needs a single jumpTo after the first frame.

  // ─── BUILD ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _showUI = !_showUI),
                  child: CustomScrollView(
                    controller: _scrollController,
                    center: _centerKey,
                    cacheExtent: 6000,
                    physics: const ClampingScrollPhysics(),
                    slivers: [
                      // ── Backward sliver (previous chapters, grows upward) ──
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            if (index >= _backwardPages.length) return null;
                            return _buildPageWidget(_backwardPages[index]);
                          },
                          childCount: _backwardPages.length,
                        ),
                      ),

                      // ── Forward sliver (initial + next chapters, grows downward) ──
                      SliverList(
                        key: _centerKey,
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            if (index >= _forwardPages.length) return null;
                            return _buildPageWidget(_forwardPages[index]);
                          },
                          childCount: _forwardPages.length,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Top AppBar overlay ──
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
                        title: Text(_currentChapterTitle),
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

                // ── Page indicator at bottom ──
                if (_currentChapterTotalPages > 0)
                  Positioned(
                    bottom: 16,
                    left: 0,
                    right: 0,
                    child: AnimatedOpacity(
                      opacity: _showUI ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            '${_currentPageInChapter + 1} / $_currentChapterTotalPages',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // ── Loading indicator for previous chapter ──
                if (_isFetchingPrev)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 60,
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

                // ── Loading indicator for next chapter ──
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

  Widget _buildPageWidget(ReaderPage page) {
    if (page.isSeparator) {
      return _buildChapterSeparator(page.chapterTitle);
    }

    Widget imageWidget;
    if (page.file != null) {
      imageWidget = Image.file(
        page.file!,
        fit: BoxFit.contain,
        width: double.infinity,
        cacheWidth: 1200,
        errorBuilder: (context, error, stackTrace) => _errorPlaceholder(),
      );
    } else {
      imageWidget = CachedNetworkImage(
        imageUrl: page.url!,
        fit: BoxFit.contain,
        width: double.infinity,
        memCacheWidth: 1200,
        fadeInDuration: const Duration(milliseconds: 100),
        placeholderFadeInDuration: Duration.zero,
        placeholder: (context, url) => _placeholder(),
        errorWidget: (context, url, error) => _errorPlaceholder(),
      );
    }

    return RepaintBoundary(
      key: page.key,
      child: imageWidget,
    );
  }

  Widget _buildChapterSeparator(String title) {
    return Container(
      height: 80,
      color: Colors.grey[900],
      child: Center(
        child: Text(
          title,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      height: 600,
      color: Colors.grey[900],
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white24,
          ),
        ),
      ),
    );
  }

  Widget _errorPlaceholder() {
    return Container(
      height: 400,
      color: Colors.grey[900],
      child: const Center(
        child: Icon(Icons.broken_image, color: Colors.white38),
      ),
    );
  }
}

class ReaderPage {
  final String chapterUrl;
  final String chapterTitle;
  final String? url;
  final File? file;
  final bool isSeparator;
  final GlobalKey key = GlobalKey();

  ReaderPage({
    required this.chapterUrl,
    required this.chapterTitle,
    this.url,
    this.file,
    this.isSeparator = false,
  });
}
