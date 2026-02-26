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
  final String sourceId;

  const ChapterReaderScreen({
    Key? key,
    required this.allChapters,
    required this.initialIndex,
    required this.sourceId,
  }) : super(key: key);

  @override
  State<ChapterReaderScreen> createState() => _ChapterReaderScreenState();
}

class _ChapterReaderScreenState extends State<ChapterReaderScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = true;
  bool _showUI = true;
  
  // List of images correctly mapped to their chapter for reading progress
  final List<ReaderPage> _pages = [];
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
    
    // Auto-mark as read logic: if we are near the end of a chapter's pages
    // We determine current chapter by looking at the page at roughly the center/top
    final currentOffset = _scrollController.offset;
    // For simplicity, we mark the *last* loaded chapter as read if we are near the very bottom
    if (_scrollController.position.pixels > _scrollController.position.maxScrollExtent - 500) {
       final lastChapterUrl = _pages.last.chapterUrl;
       if (!HistoryDB.isRead(lastChapterUrl)) {
          HistoryDB.markAsRead(lastChapterUrl, isRead: true);
       }
    }

    // Load next chapter logic
    if (_scrollController.position.pixels > _scrollController.position.maxScrollExtent - 2000) {
      if (!_isFetchingNext && _currentChapterIndex > 0) { // Chapters are usually list latest-first, so "next" is index-1
         _loadNextChapter();
      }
    }
  }

  Future<void> _fetchChapter(Chapter chapter) async {
    setState(() => _isFetchingNext = true);
    try {
      if (DownloadDB.isDownloaded(chapter.url)) {
        final download = DownloadDB.getDownload(chapter.url);
        if (download != null) {
          final dir = Directory(download.directoryPath);
          if (await dir.exists()) {
            final files = dir.listSync().whereType<File>().toList();
            files.sort((a, b) => a.path.compareTo(b.path));
            setState(() {
              _pages.addAll(files.map((f) => ReaderPage(
                chapterUrl: chapter.url,
                chapterTitle: chapter.title,
                file: f,
              )));
              _isLoading = false;
              _isFetchingNext = false;
            });
            return;
          }
        }
      }

      final parser = getParserForSite(widget.sourceId);
      final list = await parser.fetchChapterImages(chapter.url);
      setState(() {
        _pages.addAll(list.map((url) => ReaderPage(
          chapterUrl: chapter.url,
          chapterTitle: chapter.title,
          url: url,
        )));
        _isLoading = false;
        _isFetchingNext = false;
      });
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

  void _loadNextChapter() {
     _currentChapterIndex--; // Next chapter in a latest-first list
     _fetchChapter(widget.allChapters[_currentChapterIndex]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      appBar: _showUI 
        ? AppBar(
            title: Text(_pages.isNotEmpty ? _pages.last.chapterTitle : widget.allChapters[widget.initialIndex].title),
            backgroundColor: Colors.black.withOpacity(0.7),
            elevation: 0,
          )
        : null,
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
                      if (page.file != null) {
                        return Image.file(
                          page.file!,
                          fit: BoxFit.contain,
                          cacheWidth: 1200,
                          errorBuilder: (context, error, stackTrace) => _errorPlaceholder(),
                        );
                      } else {
                        return CachedNetworkImage(
                          imageUrl: page.url!,
                          fit: BoxFit.contain,
                          memCacheWidth: 1200,
                          placeholder: (context, url) => _placeholder(index),
                          errorWidget: (context, url, error) => _errorPlaceholder(),
                        );
                      }
                    },
                  ),
                ),
                if (!_showUI)
                   Positioned(
                     bottom: 20,
                     right: 20,
                     child: Container(
                       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                       decoration: BoxDecoration(
                         color: Colors.black54,
                         borderRadius: BorderRadius.circular(20),
                       ),
                       child: Text(
                         'Seamless Reading ON',
                         style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
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
