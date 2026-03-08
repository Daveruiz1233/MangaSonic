import 'package:manga_sonic/parser/base_parser.dart';
import 'package:manga_sonic/parser/manhuatop_parser.dart';
import 'package:manga_sonic/parser/asuracomic_parser.dart';
import 'package:manga_sonic/parser/manhuaplus_parser.dart';
import 'package:manga_sonic/parser/template_parser.dart';
import 'package:manga_sonic/data/db/custom_source_db.dart';

BaseParser getParserForSite(String siteName) {
  final normalized = siteName
      .toLowerCase()
      .replaceAll(' ', '')
      .replaceAll('-', '');
  switch (normalized) {
    case 'manhuatop':
      return ManhuaTopParser();
    case 'asura':
    case 'asuracomic':
    case 'asurascan':
    case 'asurascans':
      return AsuraComicParser();
    case 'manhuaplus':
      return ManhuaPlusParser();
    default:
      // Fall through to custom source lookup before throwing
      final customSource = CustomSourceDB.getSource(normalized);
      if (customSource != null) {
        return TemplateParser(customSource);
      }
      // Also try matching by iterating all custom sources
      final allCustom = CustomSourceDB.getSources();
      for (final source in allCustom) {
        if (source.sourceId == normalized ||
            source.name.toLowerCase().replaceAll(' ', '').replaceAll('-', '') ==
                normalized) {
          return TemplateParser(source);
        }
      }
      throw Exception('Parser for site $siteName not implemented');
  }
}
