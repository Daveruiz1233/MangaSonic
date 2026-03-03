import 'package:flutter_test/flutter_test.dart';
import 'package:manga_sonic/parser/asuracomic_parser.dart';
import 'package:manga_sonic/data/models/models.dart';
import 'dart:io';

void main() {
  test('AsuraComicParser verification', () async {
    final parser = AsuraComicParser();

    print('--- Testing fetchMangaList ---');
    final list = await parser.fetchMangaList(1);
    print('Fetched ${list.length} manga from page 1');
    expect(list, isNotEmpty, reason: 'Manga list should not be empty');
    print('First item: ${list.first.title} (${list.first.url})');
    print('Cover URL: ${list.first.coverUrl}');

    print('\n--- Testing searchManga ---');
    final searchResults = await parser.searchManga('solo', 1);
    print('Found ${searchResults.length} results for "solo"');
    expect(searchResults, isNotEmpty, reason: 'Search results should not be empty');
    print('First result: ${searchResults.first.title} (${searchResults.first.url})');

    print('\n--- Testing fetchMangaDetails ---');
    final manga = searchResults.first;
    final details = await parser.fetchMangaDetails(manga);
    print('Title: ${manga.title}');
    print('Author: ${details.author}');
    print('Status: ${details.status}');
    print('Genres: ${details.genres.join(", ")}');
    print('Chapter count: ${details.chapters.length}');
    print('Description length: ${details.description.length}');
    
    expect(details.chapters, isNotEmpty, reason: 'Chapters should not be empty');

    print('\n--- Testing fetchChapterImages ---');
    final chapter = details.chapters.first;
    print('Testing chapter: ${chapter.title} (${chapter.url})');
    final images = await parser.fetchChapterImages(chapter.url);
    print('Found ${images.length} images');
    expect(images, isNotEmpty, reason: 'Images should not be empty');
    print('First image: ${images.first}');

    print('\nSUCCESS: All tests passed!');
  }, timeout: Timeout(Duration(minutes: 5)));
}
