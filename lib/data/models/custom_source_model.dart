/// Template/CMS type detected for a custom manga source.
enum TemplateType {
  madara,
  mangareader,
  rsc,
  aiGenerated,
  generic;

  String toJson() => name;

  static TemplateType fromJson(String value) {
    switch (value) {
      case 'madara':
        return TemplateType.madara;
      case 'mangareader':
        return TemplateType.mangareader;
      case 'rsc':
        return TemplateType.rsc;
      case 'ai_generated':
      case 'aiGenerated':
        return TemplateType.aiGenerated;
      default:
        return TemplateType.generic;
    }
  }

  String get displayName {
    switch (this) {
      case TemplateType.madara:
        return 'Madara/WordPress';
      case TemplateType.mangareader:
        return 'MangaReader PHP';
      case TemplateType.rsc:
        return 'RSC/React';
      case TemplateType.aiGenerated:
        return 'AI Generated';
      case TemplateType.generic:
        return 'Generic';
    }
  }
}

/// A user-added custom manga source, persisted in Hive.
class CustomSourceModel {
  final String sourceId;
  final String name;
  final String url;
  final String logoUrl;
  final TemplateType templateType;
  final Map<String, String> selectors;
  final int addedAt;

  CustomSourceModel({
    required this.sourceId,
    required this.name,
    required this.url,
    required this.logoUrl,
    required this.templateType,
    required this.selectors,
    required this.addedAt,
  });

  /// Derive a sourceId from a domain string.
  /// e.g. `mangakakalot.com` → `mangakakalot`
  static String deriveSourceId(String domain) {
    return domain
        .replaceAll(RegExp(r'^www\.'), '')
        .split('.')
        .first
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// Auto-generate a favicon URL via Google's S2 API.
  static String faviconUrl(String domain) {
    return 'https://www.google.com/s2/favicons?domain=$domain&sz=128';
  }

  Map<String, dynamic> toMap() => {
        'sourceId': sourceId,
        'name': name,
        'url': url,
        'logoUrl': logoUrl,
        'templateType': templateType.toJson(),
        'selectors': selectors,
        'addedAt': addedAt,
      };

  factory CustomSourceModel.fromMap(Map<dynamic, dynamic> map) {
    return CustomSourceModel(
      sourceId: map['sourceId'] as String,
      name: map['name'] as String,
      url: map['url'] as String,
      logoUrl: map['logoUrl'] as String,
      templateType: TemplateType.fromJson(map['templateType'] as String),
      selectors: Map<String, String>.from(map['selectors'] as Map),
      addedAt: map['addedAt'] as int? ?? 0,
    );
  }

  CustomSourceModel copyWith({
    String? sourceId,
    String? name,
    String? url,
    String? logoUrl,
    TemplateType? templateType,
    Map<String, String>? selectors,
    int? addedAt,
  }) {
    return CustomSourceModel(
      sourceId: sourceId ?? this.sourceId,
      name: name ?? this.name,
      url: url ?? this.url,
      logoUrl: logoUrl ?? this.logoUrl,
      templateType: templateType ?? this.templateType,
      selectors: selectors ?? this.selectors,
      addedAt: addedAt ?? this.addedAt,
    );
  }
}
