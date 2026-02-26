import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:manga_sonic/data/db/download_db.dart';
import 'package:manga_sonic/utils/parser_factory.dart';

class ChapterReaderScreen extends StatefulWidget {
  final String chapterTitle;
  final String chapterUrl;
  final String sourceId;

  const ChapterReaderScreen({
    Key? key,
    required this.chapterTitle,
    required this.chapterUrl,
    required this.sourceId,
  }) : super(key: key);

  @override
  State<ChapterReaderScreen> createState() => _ChapterReaderScreenState();
}

class _ChapterReaderScreenState extends State<ChapterReaderScreen> {
  bool _isLoading = true;
  bool _isOffline = false;
  
  List<String> _onlineImages = [];
  List<File> _offlineImages = [];

  @override
  void initState() {
    super.initState();
    _checkAndFetchImages();
  }

  Future<void> _checkAndFetchImages() async {
    try {
      if (DownloadDB.isDownloaded(widget.chapterUrl)) {
        // STRICT OFFLINE POLICY
        _isOffline = true;
        final download = DownloadDB.getDownload(widget.chapterUrl);
        if (download != null) {
          final dir = Directory(download.directoryPath);
          if (await dir.exists()) {
            final files = dir.listSync().whereType<File>().toList();
            files.sort((a, b) => a.path.compareTo(b.path));
            if (files.isEmpty) {
              throw Exception('Offline chapter corrupted or empty.');
            }
            setState(() {
              _offlineImages = files;
              _isLoading = false;
            });
            return;
          } else {
             throw Exception('Offline map corresponds to a deleted folder. Corrupted state.');
          }
        }
      }

      // ONLINE POLICY
      final parser = getParserForSite(widget.sourceId);
      final list = await parser.fetchChapterImages(widget.chapterUrl);
      setState(() {
        _onlineImages = list;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.chapterTitle} ${_isOffline ? "(Offline)" : ""}'),
        backgroundColor: Colors.black.withOpacity(0.5),
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _isOffline ? _offlineImages.length : _onlineImages.length,
              cacheExtent: 3000, // Preload ~3-5 images ahead
              itemBuilder: (context, index) {
                if (_isOffline) {
                  return Image.file(
                    _offlineImages[index],
                    fit: BoxFit.contain,
                    cacheWidth: 1200, // Memory constraint: decode to 1200px max
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 400,
                      color: Colors.grey[900],
                      child: const Center(child: Icon(Icons.broken_image, color: Colors.white)),
                    ),
                  );
                } else {
                  return CachedNetworkImage(
                    imageUrl: _onlineImages[index],
                    fit: BoxFit.contain,
                    memCacheWidth: 1200, // Memory constraint: decode to 1200px max
                    placeholder: (context, url) => Container(
                      height: 400,
                      color: Colors.grey[900],
                      child: Center(
                        child: Text(
                          'Page ${index + 1}',
                          style: const TextStyle(color: Colors.white54),
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      height: 400,
                      color: Colors.grey[900],
                      child: const Center(child: Icon(Icons.broken_image, color: Colors.white)),
                    ),
                  );
                }
              },
            ),
    );
  }
}
