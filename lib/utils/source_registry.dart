class SourceRegistry {
  /// Map of source IDs to their display names.
  /// Includes aliases for backward compatibility.
  static const Map<String, String> displayNames = {
    'asura': 'Asura Scans',
    'asuracomic': 'Asura Scans',
    'manhuatop': 'ManhuaTop',
    'manhuaplus': 'Manhua Plus',
  };

  /// List of canonical source IDs.
  static const List<String> allSourceIds = [
    'asuracomic',
    'manhuatop',
    'manhuaplus',
  ];

  /// Gets the display name for a source ID, falling back to upper-cased ID if not found.
  static String getDisplayName(String sourceId) {
    return displayNames[sourceId] ?? sourceId.toUpperCase();
  }
}
