import 'package:manga_sonic/parser/base_parser.dart';
import 'package:manga_sonic/parser/manhuatop_parser.dart';
import 'package:manga_sonic/parser/asuracomic_parser.dart';
import 'package:manga_sonic/parser/manhuaplus_parser.dart';

BaseParser getParserForSite(String siteName) {
  switch (siteName) {
    case 'ManhuaTop':
      return ManhuaTopParser();
    case 'AsuraComic':
      return AsuraComicParser();
    case 'ManhuaPlus':
      return ManhuaPlusParser();
    default:
      throw Exception('Parser for site $siteName not implemented');
  }
}
