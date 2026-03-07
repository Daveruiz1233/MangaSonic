import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:manga_sonic/data/models/models.dart';
import 'package:manga_sonic/utils/parser_factory.dart';
import 'package:manga_sonic/utils/migration_utils.dart';
import 'package:manga_sonic/ui/screens/manga_screen.dart';

class MigrationPreviewSheet extends StatefulWidget {
  final Manga targetManga;
  final Manga sourceManga;
  final List<Chapter> sourceChapters;

  const MigrationPreviewSheet({
    super.key,
    required this.targetManga,
    required this.sourceManga,
    required this.sourceChapters,
  });

  @override
  State<MigrationPreviewSheet> createState() => _MigrationPreviewSheetState();
}

class _MigrationPreviewSheetState extends State<MigrationPreviewSheet> {
  MangaDetails? _details;
  bool _isLoading = true;
  Color? _dominantColor;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchDetails();
    _extractPalette();
  }

  Future<void> _extractPalette() async {
    try {
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(widget.targetManga.coverUrl),
        maximumColorCount: 20,
      );
      if (mounted) {
        setState(() {
          _dominantColor = paletteGenerator.dominantColor?.color;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchDetails() async {
    try {
      final parser = getParserForSite(widget.targetManga.sourceId);
      final details = await parser.fetchMangaDetails(widget.targetManga);
      if (mounted) {
        setState(() {
          _details = details;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  String _getSourceName(String id) {
    switch (id) {
      case 'asuracomic': return 'Asura Scans';
      case 'manhuatop': return 'ManhuaTop';
      case 'manhuaplus': return 'Manhua Plus';
      default: return id.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _dominantColor ?? Colors.deepPurpleAccent;
    final isDark = ThemeData.estimateBrightnessForColor(accent) == Brightness.dark;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.grey[950],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Stack(
        children: [
          // Blurred background
          if (!_isLoading && _error == null)
            Positioned.fill(
              child: Opacity(
                opacity: 0.4,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: CachedNetworkImage(
                    imageUrl: widget.targetManga.coverUrl,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          
          // Gradient overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.4),
                    Colors.black.withValues(alpha: 0.9),
                  ],
                ),
              ),
            ),
          ),

          // Main Content
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                if (_isLoading)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(40.0),
                    child: CircularProgressIndicator(),
                  ))
                else if (_error != null)
                  Center(child: Text('Error: $_error', style: const TextStyle(color: Colors.redAccent)))
                else ...[
                  // Header Info
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: widget.targetManga.coverUrl,
                          width: 100,
                          height: 140,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.targetManga.title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: accent.withValues(alpha: 0.4), width: 1),
                              ),
                              child: Text(
                                _getSourceName(widget.targetManga.sourceId),
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _infoRow(Icons.person_outline, _details!.author),
                            _infoRow(Icons.info_outline, _details!.status),
                            _infoRow(Icons.list, '${_details!.chapters.length} Chapters'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Truncated Description
                  Text(
                    _details!.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  const SizedBox(height: 32),
                  // Migration Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: isDark ? Colors.white : Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 8,
                        shadowColor: accent.withValues(alpha: 0.5),
                      ),
                      onPressed: () async {
                        // Show loading
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => const Center(child: CircularProgressIndicator()),
                        );

                        await MigrationUtils.transferProgress(
                          oldManga: widget.sourceManga,
                          newManga: widget.targetManga,
                          oldChapters: widget.sourceChapters,
                          newChapters: _details!.chapters,
                        );

                        if (context.mounted) {
                          Navigator.pop(context); // Pop loading
                          Navigator.pop(context); // Pop migration preview
                          
                          // Navigate to new manga screen (replaces current stack)
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MangaScreen(
                                mangaTitle: widget.targetManga.title,
                                mangaUrl: widget.targetManga.url,
                                coverUrl: widget.targetManga.coverUrl,
                                sourceId: widget.targetManga.sourceId,
                              ),
                            ),
                          );
                        }
                      },
                      child: const Text(
                        'MIGRATE NOW',
                        style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.white38),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
