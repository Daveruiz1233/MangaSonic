import 'package:flutter/material.dart';
import 'chapter_reader_screen.dart';

class MangaScreen extends StatefulWidget {
  final String mangaTitle;
  final String mangaUrl;
  final String coverUrl;

  const MangaScreen({
    Key? key,
    required this.mangaTitle,
    required this.mangaUrl,
    required this.coverUrl,
  }) : super(key: key);

  @override
  State<MangaScreen> createState() => _MangaScreenState();
}

class _MangaScreenState extends State<MangaScreen> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.mangaTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: () {
              // Show dialog to add to category
            },
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: 20, // Fake chapters
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text('Chapter ${20 - index}'),
                  trailing: const Icon(Icons.download),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChapterReaderScreen(
                          chapterTitle: 'Chapter ${20 - index}',
                          chapterUrl: '/dummy/chapter/$index',
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
