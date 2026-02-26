import 'package:manga_sonic/parser/manhuatop_parser.dart';
import 'dart:io';

void main() async {
  final parser = ManhuaTopParser();
  final mangaUrl = 'https://manhuatop.org/manhua/martial-peak/';
  print('Fetching chapters for: $mangaUrl');
  
  try {
    final chapters = await parser.fetchChapters(mangaUrl);
    print('Found ${chapters.length} chapters');
    for (var i = 0; i < 5 && i < chapters.length; i++) {
      print('  ${chapters[i].title}: ${chapters[i].url}');
    }
  } catch (e) {
    print('Error: $e');
  }
}
