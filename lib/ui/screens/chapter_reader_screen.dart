import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:manga_sonic/data/db/download_db.dart';
import 'package:manga_sonic/data/db/history_db.dart';
import 'package:manga_sonic/data/models/models.dart';
import 'package:manga_sonic/utils/parser_factory.dart';
import 'package:manga_sonic/utils/memory_safety_manager.dart';

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

  // Forward pages = target page + rest of chapter + next chapters (scroll down)
  // Backward pages = pages before target + previous chapters (scroll up)
  final List<ReaderPage> _forwardPages = [];
  final List<ReaderPage> _backwardPages = [];

  bool _isLoading = true;
  bool _isFetchingNext = false;
  bool _isFetchingPrev = false;

  int _topChapterIndex = 0;
  int _bottomChapterIndex = 0;

  int _activeStartIndex = -1;
  int _activeEndIndex = -1;

  StreamSubscription? _memoryPressureSub;
  bool _emergencyMode = false;

  // Progress tracking — uses ValueNotifier so updates DON'T rebuild the
  // CustomScrollView. Only the overlay widgets listening to these rebuild.
  final ValueNotifier<String> _chapterTitleNotifier = ValueNotifier('');
  final ValueNotifier<String> _pageInfoNotifier = ValueNotifier('');
  final ValueNotifier<bool> _showUINotifier = ValueNotifier(true);

  DateTime _lastSaveTime = DateTime.now();
  final Set<String> _loadedChapterUrls = {};

  @override
  void initState() {
    super.initState();
    _topChapterIndex = widget.initialIndex;
    _bottomChapterIndex = widget.initialIndex;
    _chapterTitleNotifier.value = widget.allChapters[widget.initialIndex].title;

    _scrollController = ScrollController();
    _scrollController.addListener(_onCombinedListener);

    _fetchInitialChapter();
    _listenToMemoryPressure();
  }

  void _listenToMemoryPressure() {
    _memoryPressureSub = MemorySafetyManager().lowMemoryStream.listen((isLow) {
      if (mounted) {
        setState(() {
          _emergencyMode = isLow;
        });
        _updateVisibilityWindow();
      }
    });
  }

  void _onCombinedListener() {
    _onScroll();
    _updateVisibilityWindow();
  }

  void _updateVisibilityWindow() {
    if (!_scrollController.hasClients) return;
    
    final allPages = [..._backwardPages.reversed, ..._forwardPages];
    if (allPages.isEmpty) return;

    final viewportHeight = _scrollController.position.viewportDimension;
    final scrollOffset = _scrollController.offset;

    // Use the existing render box tracking to find the "current" index 
    // and mark surrounding pages as 'near'.
    
    int centerIndex = -1;
    double closestToCenter = double.infinity;

    for (int i = 0; i < allPages.length; i++) {
        final page = allPages[i];
        if (page.isSeparator) continue;
        final ctx = page.key.currentContext;
        if (ctx == null) continue;
        final box = ctx.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) continue;
        
        final pos = box.localToGlobal(Offset.zero);
        final centerDelta = (pos.dy - (viewportHeight / 2)).abs();
        
        if (centerDelta < closestToCenter) {
            closestToCenter = centerDelta;
            centerIndex = i;
        }
    }

    if (centerIndex != -1) {
        final backwardCount = _emergencyMode ? 2 : 5;
        final forwardCount = _emergencyMode ? 5 : 10;
        
        setState(() {
            _activeStartIndex = (centerIndex - backwardCount).clamp(0, allPages.length - 1);
            _activeEndIndex = (centerIndex + forwardCount).clamp(0, allPages.length - 1);
        });
    }
  }

  @override
  void dispose() {
    _memoryPressureSub?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _chapterTitleNotifier.dispose();
    _pageInfoNotifier.dispose();
    _showUINotifier.dispose();
    super.dispose();
  }

  // ─── SCROLL HANDLING ───────────────────────────────────────────────────

  void _onScroll() {
    if (_forwardPages.isEmpty && _backwardPages.isEmpty) return;
    _trackProgress();
    _checkLoadThresholds();
  }

  void _trackProgress() {
    final now = DateTime.now();
    if (now.difference(_lastSaveTime) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastSaveTime = now;

    bool foundVisible = false;

    // Check backward pages (furthest up → closest to center)
    for (int i = _backwardPages.length - 1; i >= 0 && !foundVisible; i--) {
      final page = _backwardPages[i];
      if (page.isSeparator) continue;
      final ctx = page.key.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final pos = box.localToGlobal(Offset.zero);
      foundVisible = _processPageForTracking(
        page, pos.dy, pos.dy + box.size.height,
        isForward: false, localIndex: i,
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
      foundVisible = _processPageForTracking(
        page, pos.dy, pos.dy + box.size.height,
        isForward: true, localIndex: i,
      );
    }
  }

  bool _processPageForTracking(
    ReaderPage page, double top, double bottom, {
    required bool isForward, required int localIndex,
  }) {
    if (bottom < 0) {
      bool isLastOfChapter;
      if (isForward) {
        isLastOfChapter = localIndex == _forwardPages.length - 1 ||
            _forwardPages[localIndex + 1].chapterUrl != page.chapterUrl;
      } else {
        isLastOfChapter = localIndex == 0 ||
            _backwardPages[localIndex - 1].chapterUrl != page.chapterUrl;
      }
      if (isLastOfChapter && !HistoryDB.isRead(page.chapterUrl)) {
        HistoryDB.markAsRead(page.chapterUrl, isRead: true);
      }
      return false;
    }

    if (bottom > 10) {
      final offsetWithinPage = top < 0 ? top.abs() : 0.0;

      int pageIndexInChapter = 0;
      if (isForward) {
        for (int k = localIndex - 1; k >= 0; k--) {
          final p = _forwardPages[k];
          if (p.isSeparator) continue;
          if (p.chapterUrl == page.chapterUrl) {
            pageIndexInChapter++;
          } else {
            break;
          }
        }
        // Count same-chapter pages in backward sliver too (split initial chapter)
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

      int totalPages = 0;
      for (final p in _backwardPages) {
        if (!p.isSeparator && p.chapterUrl == page.chapterUrl) totalPages++;
      }
      for (final p in _forwardPages) {
        if (!p.isSeparator && p.chapterUrl == page.chapterUrl) totalPages++;
      }

      // Update notifiers — these do NOT trigger a CustomScrollView rebuild
      _chapterTitleNotifier.value = page.chapterTitle;
      _pageInfoNotifier.value = '${pageIndexInChapter + 1} / $totalPages';

      HistoryDB.saveProgress(
        page.chapterUrl,
        pageIndexInChapter,
        lastPageOffset: offsetWithinPage,
      );
      return true;
    }

    return false;
  }

  void _checkLoadThresholds() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;

    if (pos.pixels < pos.minScrollExtent + 3000) {
      if (!_isFetchingPrev &&
          _topChapterIndex < widget.allChapters.length - 1) {
        _loadPrevChapter();
      }
    }

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

    // Split at target page: before → backward sliver, from target → forward sliver
    final splitIndex = widget.initialPage.clamp(0, pages.length);

    if (splitIndex > 0) {
      _backwardPages.addAll(pages.sublist(0, splitIndex).reversed);
    }
    _forwardPages.addAll(pages.sublist(splitIndex));

    setState(() => _isLoading = false);

    if (widget.initialOffset > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(widget.initialOffset.clamp(
            0.0, _scrollController.position.maxScrollExtent,
          ));
        }
      });
    }

    _prefetchAdjacentChapters();
    _startHeadlessResolution(pages);
  }

  void _startHeadlessResolution(List<ReaderPage> pages) {
    for (final page in pages) {
      if (page.aspectRatio != null || page.isSeparator) continue;
      
      final provider = page.file != null 
          ? FileImage(page.file!) 
          : CachedNetworkImageProvider(page.url!) as ImageProvider;

      final stream = provider.resolve(const ImageConfiguration());
      late ImageStreamListener listener;
      listener = ImageStreamListener((info, _) {
        if (mounted) {
          final aspect = info.image.width / info.image.height;
          setState(() {
            page.aspectRatio = aspect;
          });
        }
        stream.removeListener(listener);
      });
      stream.addListener(listener);
    }
  }

  Future<List<ReaderPage>?> _fetchChapterPages(Chapter chapter) async {
    List<ReaderPage> pages = [];

    if (DownloadDB.isDownloaded(chapter.url)) {
      final download = DownloadDB.getDownload(chapter.url);
      if (download != null) {
        final dir = Directory(download.directoryPath);
        if (await dir.exists()) {
          final files = dir.listSync().whereType<File>().toList();
          files.sort((a, b) => a.path.compareTo(b.path));
          pages = files
              .map((f) => ReaderPage(
                    chapterUrl: chapter.url,
                    chapterTitle: chapter.title,
                    file: f,
                  ))
              .toList();
        }
      }
    }

    if (pages.isEmpty) {
      final parser = getParserForSite(widget.sourceId);
      try {
        final urls = await parser.fetchChapterImages(chapter.url);
        pages = urls
            .map((url) => ReaderPage(
                  chapterUrl: chapter.url,
                  chapterTitle: chapter.title,
                  url: url,
                ))
            .toList();
      } catch (e) {
        debugPrint('Chapter fetch error: $e');
        if (mounted) _showOfflineDialog();
        return null;
      }
    }

    for (int i = 0; i < pages.length && i < 5; i++) {
      final url = pages[i].url;
      if (url != null) {
        try {
          CachedNetworkImageProvider(url).resolve(ImageConfiguration.empty);
        } catch (_) {}
      }
    }

    return pages;
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

  void _loadNextChapter() {
    if (_isFetchingNext) return;
    final nextIndex = _bottomChapterIndex - 1;
    if (nextIndex < 0) return;
    final chapter = widget.allChapters[nextIndex];
    if (_loadedChapterUrls.contains(chapter.url)) return;

    _isFetchingNext = true;

    _fetchChapterPages(chapter).then((pages) {
      if (pages != null && pages.isNotEmpty && mounted) {
        _loadedChapterUrls.add(chapter.url);
        _bottomChapterIndex = nextIndex;

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
        _startHeadlessResolution(pages);
      } else if (mounted) {
        _isFetchingNext = false;
      }
    });
  }

  void _loadPrevChapter() {
    if (_isFetchingPrev) return;
    final prevIndex = _topChapterIndex + 1;
    if (prevIndex >= widget.allChapters.length) return;
    final chapter = widget.allChapters[prevIndex];
    if (_loadedChapterUrls.contains(chapter.url)) return;

    _isFetchingPrev = true;

    _fetchChapterPages(chapter).then((pages) {
      if (pages != null && pages.isNotEmpty && mounted) {
        _loadedChapterUrls.add(chapter.url);
        _topChapterIndex = prevIndex;

        final separator = ReaderPage(
          chapterUrl: chapter.url,
          chapterTitle: chapter.title,
          isSeparator: true,
        );

        setState(() {
          _backwardPages.addAll(pages.reversed);
          _backwardPages.add(separator);
          _isFetchingPrev = false;
        });
        _startHeadlessResolution(pages);
      } else if (mounted) {
        _isFetchingPrev = false;
      }
    });
  }

  void _prefetchAdjacentChapters() {
    if (_bottomChapterIndex > 0) {
      final nextChapter = widget.allChapters[_bottomChapterIndex - 1];
      if (DownloadDB.isDownloaded(nextChapter.url)) {
        _loadNextChapter();
      }
    }
    if (_topChapterIndex < widget.allChapters.length - 1) {
      final prevChapter = widget.allChapters[_topChapterIndex + 1];
      if (DownloadDB.isDownloaded(prevChapter.url)) {
        _loadPrevChapter();
      }
    }
  }

  // ─── BUILD ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // ── The scroll view — ONLY rebuilds when pages are added ──
                GestureDetector(
                  onTap: () => _showUINotifier.value = !_showUINotifier.value,
                  child: CustomScrollView(
                    controller: _scrollController,
                    center: _centerKey,
                    cacheExtent: 6000,
                    physics: const ClampingScrollPhysics(),
                    slivers: [
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            if (index >= _backwardPages.length) return null;
                            final page = _backwardPages[index];
                            return _MemoryManagedPage(
                              key: page.key,
                              page: page,
                              isNear: _isPageNearViewport(page),
                            );
                          },
                          childCount: _backwardPages.length,
                          addAutomaticKeepAlives: false,
                          findChildIndexCallback: (Key key) {
                            final idx = _backwardPages.indexWhere(
                              (p) => p.key == key,
                            );
                            return idx >= 0 ? idx : null;
                          },
                        ),
                      ),
                      SliverList(
                        key: _centerKey,
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            if (index >= _forwardPages.length) return null;
                            final page = _forwardPages[index];
                            return _MemoryManagedPage(
                              key: page.key,
                              page: page,
                              isNear: _isPageNearViewport(page),
                            );
                          },
                          childCount: _forwardPages.length,
                          addAutomaticKeepAlives: false,
                          findChildIndexCallback: (Key key) {
                            final idx = _forwardPages.indexWhere(
                              (p) => p.key == key,
                            );
                            return idx >= 0 ? idx : null;
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Overlays use ValueListenableBuilder — never rebuild slivers ──
                ValueListenableBuilder<bool>(
                  valueListenable: _showUINotifier,
                  builder: (context, showUI, _) => Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: AnimatedOpacity(
                      opacity: showUI ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: IgnorePointer(
                        ignoring: !showUI,
                        child: ValueListenableBuilder<String>(
                          valueListenable: _chapterTitleNotifier,
                          builder: (context, title, _) => AppBar(
                            title: Text(title),
                            backgroundColor:
                                Colors.black.withValues(alpha: 0.7),
                            elevation: 0,
                            leading: IconButton(
                              icon: const Icon(Icons.arrow_back),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Page indicator ──
                ValueListenableBuilder<bool>(
                  valueListenable: _showUINotifier,
                  builder: (context, showUI, _) => Positioned(
                    bottom: 16,
                    left: 0,
                    right: 0,
                    child: AnimatedOpacity(
                      opacity: showUI ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Center(
                        child: ValueListenableBuilder<String>(
                          valueListenable: _pageInfoNotifier,
                          builder: (context, pageInfo, _) {
                            if (pageInfo.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                pageInfo,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  bool _isPageNearViewport(ReaderPage page) {
    if (_activeStartIndex == -1) return true;
    final allPages = [..._backwardPages.reversed, ..._forwardPages];
    final idx = allPages.indexOf(page);
    if (idx == -1) return true;
    return idx >= _activeStartIndex && idx <= _activeEndIndex;
  }
}

class _MemoryManagedPage extends StatelessWidget {
  final ReaderPage page;
  final bool isNear;

  const _MemoryManagedPage({
    super.key,
    required this.page,
    required this.isNear,
  });

  @override
  Widget build(BuildContext context) {
    if (page.isSeparator) {
      return Container(
        height: 80,
        color: Colors.grey[900],
        child: Center(
          child: Text(
            page.chapterTitle,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: _StableImageV3(
        key: ValueKey(page.url ?? page.file?.path ?? page.chapterUrl),
        page: page,
        isNear: isNear,
      ),
    );
  }
}

/// V3 Engine: Instant zero-jump placeholders + scroll compensation.
class _StableImageV3 extends StatefulWidget {
  final ReaderPage page;
  final bool isNear;
  const _StableImageV3({super.key, required this.page, required this.isNear});

  @override
  State<_StableImageV3> createState() => _StableImageV3State();
}

class _StableImageV3State extends State<_StableImageV3> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final aspect = widget.page.aspectRatio;

        if (aspect != null) {
          final height = width / aspect;
          return SizedBox(
            width: width,
            height: height,
            child: widget.isNear ? _buildImage() : const SizedBox.shrink(),
          );
        }

        // Fallback placeholder while pre-resolving (V3 goal: should be rare)
        return SizedBox(
          width: width,
          height: 800, // Better guess for portrait manga
          child: _buildImageWithSizeDetection(width),
        );
      },
    );
  }

  Widget _buildImage() {
    // Use manual Image widget with providers to cap cache size
    final ImageProvider provider;
    if (widget.page.file != null) {
      provider = FileImage(widget.page.file!);
    } else {
      provider = CachedNetworkImageProvider(widget.page.url!);
    }

    return Image(
      image: provider,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      // Cap decoding size to save RAM on iPhone 6s Plus
      // 800-1000px is plenty for a phone screen
      filterQuality: FilterQuality.medium,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        return frame != null ? child : _loadingWidget();
      },
      errorBuilder: (_, __, ___) => _errorWidget(),
    );
  }

  Widget _buildImageWithSizeDetection(double availableWidth) {
    final ImageProvider provider;
    if (widget.page.file != null) {
      provider = FileImage(widget.page.file!);
    } else {
      provider = CachedNetworkImageProvider(widget.page.url!);
    }

    return Image(
      image: provider,
      fit: BoxFit.contain,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame != null && widget.page.aspectRatio == null) {
          _resolveSize(provider, availableWidth, context);
        }
        return frame != null ? child : _loadingWidget();
      },
      errorBuilder: (_, __, ___) => _errorWidget(),
    );
  }

  void _resolveSize(ImageProvider provider, double availableWidth, BuildContext context) {
    if (widget.page.aspectRatio != null) return;
    final stream = provider.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    
    final scrollPosition = Scrollable.maybeOf(context)?.position;

    listener = ImageStreamListener((info, _) {
      if (mounted) {
        final aspect = info.image.width / info.image.height;
        final heightDelta = (availableWidth / aspect) - 800.0;

        if (widget.page.aspectRatio == null) {
          setState(() {
            widget.page.aspectRatio = aspect;
          });

          // Accurate scroll compensation
          if (scrollPosition != null && heightDelta.abs() > 1.0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final box = context.findRenderObject() as RenderBox?;
              if (box != null && box.hasSize) {
                final pos = box.localToGlobal(Offset.zero);
                // IF top of image is ABOVE viewport center, compensate
                if (pos.dy < 0) {
                  scrollPosition.correctBy(heightDelta);
                }
              }
            });
          }
        }
      }
      stream.removeListener(listener);
    });
    stream.addListener(listener);
  }

  Widget _loadingWidget() {
    return Container(
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

  Widget _errorWidget() {
    return Container(
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
  
  double? aspectRatio;

  ReaderPage({
    required this.chapterUrl,
    required this.chapterTitle,
    this.url,
    this.file,
    this.isSeparator = false,
  });
}
