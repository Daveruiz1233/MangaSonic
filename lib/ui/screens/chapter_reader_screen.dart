import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
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

  // Forward pages = target page + rest of chapter + next chapters (scroll down)
  // Backward pages = pages before target + previous chapters (scroll up)
  final List<ReaderPage> _forwardPages = [];
  final List<ReaderPage> _backwardPages = [];

  bool _isLoading = true;
  bool _isFetchingNext = false;
  bool _isFetchingPrev = false;

  int _topChapterIndex = 0;
  int _bottomChapterIndex = 0;

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
    _scrollController.addListener(_onScroll);

    _fetchInitialChapter();
  }

  @override
  void dispose() {
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
                            return _buildPageWidget(_backwardPages[index]);
                          },
                          childCount: _backwardPages.length,
                          addAutomaticKeepAlives: true,
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
                            return _buildPageWidget(_forwardPages[index]);
                          },
                          childCount: _forwardPages.length,
                          addAutomaticKeepAlives: true,
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

  Widget _buildPageWidget(ReaderPage page) {
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
      key: page.key,
      child: _StableImage(
        key: ValueKey(page.url ?? page.file?.path ?? page.chapterUrl),
        page: page,
      ),
    );
  }
}

/// Prevents viewport shifts by locking height once the image's aspect ratio
/// is known. While loading, shows a fixed 600px placeholder. When the image
/// decodes, captures its real dimensions and constrains the SizedBox to the
/// exact height — the transition happens in ONE frame with no intermediate
/// relayout that could push other items around.
class _StableImage extends StatefulWidget {
  final ReaderPage page;
  const _StableImage({super.key, required this.page});

  @override
  State<_StableImage> createState() => _StableImageState();
}

class _StableImageState extends State<_StableImage> with AutomaticKeepAliveClientMixin {
  double? _aspectRatio;

  @override
  bool get wantKeepAlive => _aspectRatio != null;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        if (_aspectRatio != null) {
          final height = width / _aspectRatio!;
          return SizedBox(
            width: width,
            height: height,
            child: _buildImage(),
          );
        }

        return SizedBox(
          width: width,
          height: 600,
          child: _buildImageWithSizeDetection(width),
        );
      },
    );
  }

  Widget _buildImage() {
    if (widget.page.file != null) {
      return Image.file(
        widget.page.file!,
        fit: BoxFit.contain,
        width: double.infinity,
        cacheWidth: 1200,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _errorWidget(),
      );
    }
    return CachedNetworkImage(
      imageUrl: widget.page.url!,
      fit: BoxFit.contain,
      width: double.infinity,
      memCacheWidth: 1200,
      fadeInDuration: Duration.zero,
      placeholderFadeInDuration: Duration.zero,
      placeholder: (_, _) => const SizedBox.shrink(),
      errorWidget: (_, _, _) => _errorWidget(),
    );
  }

  Widget _buildImageWithSizeDetection(double availableWidth) {
    if (widget.page.file != null) {
      return Image.file(
        widget.page.file!,
        fit: BoxFit.contain,
        width: double.infinity,
        cacheWidth: 1200,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (frame != null) {
            _resolveSize(FileImage(widget.page.file!), availableWidth, context);
          }
          return frame != null ? child : _loadingWidget();
        },
        errorBuilder: (_, _, _) => _errorWidget(),
      );
    }

    return CachedNetworkImage(
      imageUrl: widget.page.url!,
      fit: BoxFit.contain,
      width: double.infinity,
      memCacheWidth: 1200,
      fadeInDuration: Duration.zero,
      placeholderFadeInDuration: Duration.zero,
      imageBuilder: (context, imageProvider) {
        _resolveSize(imageProvider, availableWidth, context);
        return Image(
          image: imageProvider,
          fit: BoxFit.contain,
          width: double.infinity,
        );
      },
      placeholder: (_, _) => _loadingWidget(),
      errorWidget: (_, _, _) => _errorWidget(),
    );
  }

  void _resolveSize(ImageProvider provider, double availableWidth, BuildContext context) {
    if (_aspectRatio != null) return;
    final stream = provider.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    
    // Grab scroll position if it exists
    final scrollPosition = Scrollable.maybeOf(context)?.position;

    listener = ImageStreamListener((info, _) {
      final w = info.image.width.toDouble();
      final h = info.image.height.toDouble();
      if (w > 0 && h > 0 && mounted) {
        final newAspect = w / h;
        final heightDelta = (availableWidth / newAspect) - 600.0;

        setState(() => _aspectRatio = newAspect);

        // Compensate scroll if we are above viewport center
        if (scrollPosition != null && heightDelta.abs() > 1.0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final box = context.findRenderObject() as RenderBox?;
            if (box != null && box.hasSize) {
              final pos = box.localToGlobal(Offset.zero);
              // If image is above viewport, adjust scroll
              if (pos.dy < 0) {
                scrollPosition.correctBy(heightDelta);
              }
            }
          });
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

  ReaderPage({
    required this.chapterUrl,
    required this.chapterTitle,
    this.url,
    this.file,
    this.isSeparator = false,
  });
}
