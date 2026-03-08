import 'package:manga_sonic/data/db/custom_source_db.dart';

class SourceRegistry {
  /// Map of built-in source IDs to their display names.
  /// Includes aliases for backward compatibility.
  static const Map<String, String> _builtInDisplayNames = {
    'asura': 'Asura Scans',
    'asuracomic': 'Asura Scans',
    'manhuatop': 'ManhuaTop',
    'manhuaplus': 'Manhua Plus',
  };

  /// List of built-in canonical source IDs.
  static const List<String> _builtInSourceIds = [
    'asuracomic',
    'manhuatop',
    'manhuaplus',
  ];

  // Cached merged maps — call refresh() to update after adding/removing custom sources.
  static Map<String, String> _cachedDisplayNames = {};
  static List<String> _cachedAllSourceIds = [];
  static bool _initialized = false;

  /// Merged display names: built-in + custom sources.
  static Map<String, String> get displayNames {
    if (!_initialized) refresh();
    return _cachedDisplayNames;
  }

  /// Merged source IDs: built-in + custom sources.
  static List<String> get allSourceIds {
    if (!_initialized) refresh();
    return _cachedAllSourceIds;
  }

  /// Rebuild the merged source lists from built-in + CustomSourceDB.
  static void refresh() {
    _cachedDisplayNames = Map<String, String>.from(_builtInDisplayNames);
    _cachedAllSourceIds = List<String>.from(_builtInSourceIds);

    try {
      final customSources = CustomSourceDB.getSources();
      for (final source in customSources) {
        _cachedDisplayNames[source.sourceId] = source.name;
        if (!_cachedAllSourceIds.contains(source.sourceId)) {
          _cachedAllSourceIds.add(source.sourceId);
        }
      }
    } catch (_) {
      // CustomSourceDB may not be initialized yet during early startup
    }

    _initialized = true;
  }

  /// Gets the display name for a source ID, falling back to upper-cased ID if not found.
  static String getDisplayName(String sourceId) {
    if (!_initialized) refresh();
    return _cachedDisplayNames[sourceId] ?? sourceId.toUpperCase();
  }
}
