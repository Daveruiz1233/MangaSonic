import 'package:manga_sonic/parser/asuracomic_parser.dart';
import 'package:manga_sonic/data/models/models.dart';

void main() async {
  final p = AsuraComicParser();

  // Test 1: fetchMangaList page 1
  print('=== fetchMangaList page 1 ===');
  final page1 = await p.fetchMangaList(1);
  print('Count: ${page1.length}');
  for (var m in page1) {
    print('  ${m.title} -> ${m.url}');
  }

  // Test 2: fetchMangaList page 2
  print('\n=== fetchMangaList page 2 ===');
  final page2 = await p.fetchMangaList(2);
  print('Count: ${page2.length}');
  for (var m in page2) {
    print('  ${m.title} -> ${m.url}');
  }

  // Check for duplicates between pages
  final p1Urls = page1.map((m) => m.url).toSet();
  final p2Urls = page2.map((m) => m.url).toSet();
  final overlap = p1Urls.intersection(p2Urls);
  print('\nDuplicates between page 1 and 2: ${overlap.length}');
  if (overlap.isNotEmpty) {
    print('  FAIL: Found duplicates:');
    for (var url in overlap) print('    $url');
  } else {
    print('  PASS: No duplicates!');
  }

  // Test 3: fetchChapters
  print('\n=== fetchChapters ===');
  final manga = page1.first;
  print('Testing with: ${manga.title} (${manga.url})');
  final chapters = await p.fetchChapters(manga.url);
  print('Chapter count: ${chapters.length}');
  for (var c in chapters) {
    print('  ${c.title} -> ${c.url}');
  }

  // Verify no "First Chapter" or "New Chapter" entries
  final badChapters = chapters.where(
    (c) => c.title == 'First Chapter' || c.title == 'New Chapter',
  );
  if (badChapters.isNotEmpty) {
    print('  FAIL: Found promo button chapters!');
  } else {
    print('  PASS: No promo button chapters!');
  }

  // Test 4: fetchChapterImages
  print('\n=== fetchChapterImages ===');
  if (chapters.isNotEmpty) {
    // Pick the first (or last) chapter
    final ch = chapters.last; // usually Chapter 1
    print('Testing with: ${ch.title} (${ch.url})');
    final images = await p.fetchChapterImages(ch.url);
    print('Image count: ${images.length}');
    for (var img in images.take(3)) {
      print('  $img');
    }
    if (images.isNotEmpty) {
      print('  PASS: Images found!');
    } else {
      print('  FAIL: No images found!');
    }
  }

  // Test 5: search
  print('\n=== searchManga ===');
  final results = await p.searchManga('demon', 1);
  print('Search "demon" results: ${results.length}');
  for (var m in results.take(5)) {
    print('  ${m.title}');
  }

  print('\n=== ALL TESTS COMPLETE ===');
}
