import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;

void main() async {
  final client = http.Client();
  final headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };

  // Test chapter image extraction using the new logic
  print('=== TEST: Chapter Image Extraction (New Logic) ===');

  for (var chapterUrl in [
    'https://asuracomic.net/series/the-demon-god-a5b82a99/chapter/1',
    'https://asuracomic.net/series/the-demon-god-a5b82a99/chapter/5',
  ]) {
    print('\n--- $chapterUrl ---');
    final resp = await client.get(Uri.parse(chapterUrl), headers: headers);
    print('Status: ${resp.statusCode}');

    final doc = parser.parse(resp.body);

    // New logic: extract from RSC scripts using numeric filename pattern
    final pagePattern = RegExp(
      r'https?://gg\.asuracomic\.net/storage/media/\d+/conversions/(\d+)-optimized\.webp',
    );

    final seen = <String>{};
    final pages = <MapEntry<int, String>>[];

    final scripts = doc.querySelectorAll('script');
    for (var script in scripts) {
      final text = script.text;
      if (!text.contains('asuracomic.net')) continue;
      for (var match in pagePattern.allMatches(text)) {
        final url = match.group(0)!;
        final pageNum = int.parse(match.group(1)!);
        if (seen.add(url)) {
          pages.add(MapEntry(pageNum, url));
        }
      }
    }

    pages.sort((a, b) => a.key.compareTo(b.key));

    print('Pages found: ${pages.length}');
    for (var p in pages) {
      print('  Page ${p.key.toString().padLeft(2, '0')}: ${p.value}');
    }

    if (pages.isNotEmpty) {
      print('>> PASS: ${pages.length} chapter pages found!');
    } else {
      print('>> FAIL: No chapter pages found!');
    }
  }

  print('\n=== ALL TESTS COMPLETE ===');
  client.close();
}
