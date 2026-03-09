import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_sonic/data/models/custom_source_model.dart';
import 'package:manga_sonic/parser/template_parser.dart';
import 'package:manga_sonic/utils/site_template_detector.dart';

void main() {
  HttpOverrides.global = null;

  final targets = [
    'https://reaperscans.com/',
    'https://flamescans.org/',
    'https://mangagg.com/',
    'https://mangatx.com/',
  ];

  test('Targeted System Validation (EMPTY Fix)', () async {
    final detector = SiteTemplateDetector();

    for (var url in targets) {
      print('--- Testing $url ---');
      try {
        final result = await detector.detect(url).timeout(const Duration(seconds: 20));
        print('Detect Result: ${result.templateType.name} (Conf: ${result.confidence})');
        
        // Debug HTML
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 10);
        final request = await client.getUrl(Uri.parse(url));
        request.headers.set('User-Agent', 'Mozilla/5.0');
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        print('Status: ${response.statusCode}');
        print('HTML Preview: ${body.substring(0, body.length > 500 ? 500 : body.length)}');

        final source = CustomSourceModel(
          sourceId: 'test',
          name: 'Test',
          url: url,
          logoUrl: '',
          templateType: result.templateType,
          selectors: result.extractedSelectors,
          addedAt: 0,
        );

        final parser = TemplateParser(source);
        final list = await parser.fetchMangaList(1);
        print('Found ${list.length} items');
        if (list.isNotEmpty) {
           print('Sample: ${list.first.title} (${list.first.url})');
        }
      } catch (e) {
        print('FAIL: $e');
      }
      print('');
    }
    detector.dispose();
  });
}
