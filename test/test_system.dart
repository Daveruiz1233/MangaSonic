import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_sonic/data/models/custom_source_model.dart';
import 'package:manga_sonic/parser/template_parser.dart';
import 'package:manga_sonic/utils/site_template_detector.dart';

void main() {
  HttpOverrides.global = null;

  final rawList = [
    'https://asurascans.com',
    'https://asuracomic.net',
    'https://reaperscans.com',
    'https://flamescans.org',
    'https://realmscans.com',
    'https://skymanga.co',
    'https://mangagg.com',
    'https://voreascan.com',
    'https://mangaread.org',
    'https://aquamanga.com',
    'https://manhwaus.com',
    'https://asura.gg',
    'https://madara.co',
    'https://manganote.com',
    'https://catmanga.org',
    'https://mangatx.com',
    'https://mangakakalot.com',
    'https://manhuaplus.top',
    'https://manhuaplus.com',
    'https://mangaowl.net',
    'https://manganato.com',
    'https://mangalife.org',
    'https://funmanga.com',
    'https://zinmanga.com',
    'https://leviatanscans.com',
    'https://mangatop.info',
    'https://manhuascan.us',
    'https://mangabuddy.com',
    'https://manganet.com',
    'https://manhuazonghe.com',
    'https://comicextra.com',
    'https://readmng.com',
    'https://readms.net',
    'https://mangafox.me',
    'https://mangareader.net',
    'https://mangastream.com',
    'https://mangafreak.net',
    'https://mangajar.com',
    'https://www.manhuakey.com',
    'https://mangazin.org',
    'https://zonataurus.com',
    'https://yonaber.com',
    'https://truyengay.net',
    'https://syosetu.st',
    'https://opiatoon.lat',
    'https://mindafansub.top',
    'https://lectormanga2.site',
    'https://mangaread.org',
    'https://comi.mobi',
    'https://coffeemanga.io',
    'https://manhuaplus.com',
    'https://manhuafast.com',
    'https://lhtranslation.net',
    'https://weebrook.com',
    'https://lekmanaga.net',
    'https://aquareader.net',
    'https://midnightmm.net',
    'https://novel-lucky.com',
    'https://mastermindcomics.net',
    'https://yuri.live',
    'https://coffeemanblogs.com',
    'https://arte9.com',
    'https://mangaowl.io',
    'https://mangago.ms',
    'https://manhuazonghe.com',
    'https://readmtl.com',
    'https://mangagg.com',
    'https://flowermanga.net',
    'https://novelokutr.net',
    'https://webtoontr.net',
    'https://asurascans.com',
    'https://tcbscans.com',
    'https://bicomic.com',
    'https://1stkissmanga.me',
    'https://tmanhua.com',
    'https://readm.org',
    'https://chapmanganato.com',
    'https://manhwaclan.com',
    'https://manhuaplus.org',
    'https://tempestfansub.com',
    'https://manga3k.net',
    'https://reaperscans.com',
    'https://reset-scans.com',
    'https://fsite.net',
    'https://mangace.com',
    'https://manhazone.com',
    'https://9manga.com',
    'https://manhwas.men',
    'https://manhuaus.com',
    'https://wuxiamanga.com',
    'https://manhwatop.com',
    'https://bato.to',
    'https://myreadingmanga.info',
    'https://manhuascan.io',
    'https://manhwabooks.com',
    'https://manhwaxa.com',
    'https://manga-buddy.com',
    'https://mangatx.com',
    'https://manhwa18.org',
    'https://mangazuki.me',
    'https://manhwas.net',
    'https://manhwa18.net',
    'https://manwatop.com',
    'https://manhuaes.com',
    'https://mangakakalot.com',
    'https://manhuaplus.net',
    'https://manhwa-manga.bid',
    'https://manhuaplus.cc',
    'https://manhwahot.com',
    'https://manhuafast.org',
    'https://manhwascan.io',
    'https://toonkor8.me',
  ];

  // Deduplicate and normalize
  final sites = rawList.map((e) => e.endsWith('/') ? e : '$e/').toSet().toList();

  test('Massive Universal System Validation', () async {
    final results = <String, Map<String, dynamic>>{};
    final detector = SiteTemplateDetector();

    print('\n========================================================');
    print('🚀 MANGA SONIC: MASSIVE SYSTEM VALIDATION');
    print('Testing ${sites.length} unique sites...');
    print('========================================================\n');

    for (var siteUrl in sites) {
      stdout.write('  - Testing $siteUrl ... ');
      
      try {
        final detectResult = await detector.detect(siteUrl).timeout(const Duration(seconds: 25));
        
        final source = CustomSourceModel(
          sourceId: CustomSourceModel.deriveSourceId(Uri.parse(siteUrl).host),
          name: 'Test',
          url: siteUrl,
          logoUrl: '',
          templateType: detectResult.templateType,
          selectors: detectResult.extractedSelectors,
          addedAt: 0,
        );

        final parser = TemplateParser(source);
        final mangaList = await parser.fetchMangaList(1).timeout(const Duration(seconds: 20));

        if (mangaList.isNotEmpty) {
          print('✅ [${detectResult.templateType.name}] Found ${mangaList.length} items');
          results[siteUrl] = {
            'status': 'PASS',
            'type': detectResult.templateType.name,
            'count': mangaList.length,
          };
        } else {
          print('⚠️ [${detectResult.templateType.name}] EMPTY');
          results[siteUrl] = {
            'status': 'EMPTY',
            'type': detectResult.templateType.name,
            'error': 'No items in manga list',
          };
        }
      } catch (e) {
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('cloudflare') || errStr.contains('403') || errStr.contains('429')) {
            print('🛡️ CLOUDFLARE');
            results[siteUrl] = {'status': 'PROTECTED', 'error': 'Cloudflare'};
        } else if (errStr.contains('timeout')) {
            print('🕒 TIMEOUT');
            results[siteUrl] = {'status': 'TIMEOUT', 'error': 'Timeout'};
        } else if (errStr.contains('host lookup') || errStr.contains('no such host')) {
            print('👻 OFFLINE');
            results[siteUrl] = {'status': 'OFFLINE', 'error': 'DNS Failure'};
        } else {
            print('❌ FAIL: $e');
            results[siteUrl] = {'status': 'FAIL', 'error': e.toString()};
        }
      }
    }

    detector.dispose();

    print('\n========================================================');
    print('📊 MASSIVE VALIDATION SCORECARD');
    print('========================================================');
    int pass = 0, protected = 0, fail = 0, empty = 0, timeout = 0, offline = 0;
    
    final failedList = <String>[];
    final emptyList = <String>[];

    for (var site in sites) {
      final data = results[site] ?? {'status': 'UNKNOWN'};
      final status = data['status'];
      if (status == 'PASS') pass++;
      if (status == 'PROTECTED') protected++;
      if (status == 'EMPTY') {
        empty++;
        emptyList.add(site);
      }
      if (status == 'TIMEOUT') timeout++;
      if (status == 'OFFLINE') offline++;
      if (status == 'FAIL') {
        fail++;
        failedList.add('$site (${data['error']})');
      }
    }

    print('Total Unique Sites:  ${sites.length}');
    print('✅ SUCCESS (Parser OK): $pass');
    print('🛡️ PROTECTED (CF/CLI): $protected');
    print('👻 OFFLINE (Shutdown): $offline');
    print('⚠️ EMPTY (Logic Gap):  $empty');
    print('🕒 TIMEOUT:            $timeout');
    print('❌ CRITICAL FAIL:       $fail');
    
    if (emptyList.isNotEmpty) {
      print('\n🔍 EMPTY LIST (Investigate):');
      for (var s in emptyList) print('  - $s');
    }

    if (failedList.isNotEmpty) {
      print('\n❌ FAIL LIST (Investigate):');
      for (var s in failedList) print('  - $s');
    }
    print('========================================================\n');
  }, timeout: const Timeout(Duration(minutes: 60))); // Long timeout for 100+ sites
}
