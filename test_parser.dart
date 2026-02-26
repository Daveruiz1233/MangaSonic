import 'package:manga_sonic/parser/manhuatop_parser.dart';

void main() async {
  final parser = ManhuaTopParser();
  print("Testing ManhuaTop Parser...");
  try {
    final list = await parser.fetchMangaList(1);
    print("Found ${list.length} mangas");
    if (list.isNotEmpty) {
      print("First manga: ${list.first.title} -> ${list.first.url}");
      final chapters = await parser.fetchChapters(list.first.url);
      print("Found ${chapters.length} chapters");
      if (chapters.isNotEmpty) {
        print("First chapter: ${chapters.first.title} -> ${chapters.first.url}");
        final images = await parser.fetchChapterImages(chapters.first.url);
        print("Found ${images.length} images");
        if (images.isNotEmpty) {
          print("First image: ${images.first}");
        }
      }
    }
  } catch (e) {
    print("Error: $e");
  }
}
