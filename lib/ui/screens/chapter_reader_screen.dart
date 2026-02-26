import 'package:flutter/material.dart';

class ChapterReaderScreen extends StatefulWidget {
  final String chapterTitle;
  final String chapterUrl;

  // We will eventually add offline check parameters

  const ChapterReaderScreen({
    Key? key,
    required this.chapterTitle,
    required this.chapterUrl,
  }) : super(key: key);

  @override
  State<ChapterReaderScreen> createState() => _ChapterReaderScreenState();
}

class _ChapterReaderScreenState extends State<ChapterReaderScreen> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chapterTitle),
        backgroundColor: Colors.black.withOpacity(0.5),
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: 10, // fake images
              itemBuilder: (context, index) {
                return Container(
                  height: 400,
                  margin: const EdgeInsets.only(bottom: 4),
                  color: Colors.grey[900],
                  child: Center(
                    child: Text('Image $index', style: const TextStyle(color: Colors.white)),
                  ),
                );
              },
            ),
    );
  }
}
