import 'package:flutter/material.dart';
import 'package:manga_sonic/ui/screens/chapter_reader_screen.dart';
import 'package:manga_sonic/data/models/models.dart';
import 'package:manga_sonic/data/db/library_db.dart';
import 'package:manga_sonic/data/models/library_models.dart';
import 'package:manga_sonic/utils/parser_factory.dart';

class MangaScreen extends StatefulWidget {
  final String mangaTitle;
  final String mangaUrl;
  final String coverUrl;
  final String sourceId;

  const MangaScreen({
    Key? key,
    required this.mangaTitle,
    required this.mangaUrl,
    required this.coverUrl,
    required this.sourceId,
  }) : super(key: key);

  @override
  State<MangaScreen> createState() => _MangaScreenState();
}

class _MangaScreenState extends State<MangaScreen> {
  bool _isLoading = true;
  List<Chapter> _chapters = [];
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    _isSaved = LibraryDB.isSaved(widget.mangaUrl);
    _fetchChapters();
  }

  Future<void> _fetchChapters() async {
    try {
      final parser = getParserForSite(widget.sourceId);
      final list = await parser.fetchChapters(widget.mangaUrl);
      setState(() {
        _chapters = list;
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
        title: Text(widget.mangaTitle),
        actions: [
          IconButton(
            icon: Icon(_isSaved ? Icons.bookmark : Icons.bookmark_add_outlined),
            onPressed: () async {
              if (_isSaved) {
                await LibraryDB.removeItem(widget.mangaUrl);
                setState(() => _isSaved = false);
              } else {
                final categories = LibraryDB.getCategories();
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
                                if (mounted) {
                                  Navigator.pop(context);
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
            },
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _chapters.length,
              itemBuilder: (context, index) {
                final chapter = _chapters[index];
                return ListTile(
                  title: Text(chapter.title),
                  trailing: const Icon(Icons.download),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChapterReaderScreen(
                          chapterTitle: chapter.title,
                          chapterUrl: chapter.url,
                          sourceId: widget.sourceId,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

