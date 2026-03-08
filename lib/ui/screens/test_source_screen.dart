import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:manga_sonic/data/db/custom_source_db.dart';
import 'package:manga_sonic/data/models/custom_source_model.dart';
import 'package:manga_sonic/data/models/models.dart';
import 'package:manga_sonic/parser/template_parser.dart';
import 'package:manga_sonic/services/nim_ai_service.dart';
import 'package:manga_sonic/ui/widgets/ai_log_panel.dart';

/// Interactive source validation screen where the user drills down
/// from manga list → chapters → reading test to verify end-to-end.
class TestSourceScreen extends StatefulWidget {
  final CustomSourceModel source;
  final String rawHtml;
  final NimAiService aiService;

  const TestSourceScreen({
    super.key,
    required this.source,
    required this.rawHtml,
    required this.aiService,
  });

  @override
  State<TestSourceScreen> createState() => _TestSourceScreenState();
}

class _TestSourceScreenState extends State<TestSourceScreen> {
  late TemplateParser _parser;
  final _logController = AiLogController();
  final _feedbackController = TextEditingController();
  late CustomSourceModel _source;

  // Step 1 — Manga list
  List<Manga> _mangaList = [];
  bool _loadingManga = true;
  String? _mangaError;

  // Step 2 — Chapters
  Manga? _selectedManga;
  List<Chapter> _chapters = [];
  bool _loadingChapters = false;
  String? _chapterError;

  // Step 3 — Images
  Chapter? _selectedChapter;
  List<String> _images = [];
  bool _loadingImages = false;
  String? _imageError;

  // Validation state
  bool _readingTestPassed = false;
  bool _showAiFeedback = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _source = widget.source;
    _parser = TemplateParser(_source);
    _fetchMangaList();
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    _logController.dispose();
    super.dispose();
  }

  // ── Data fetching ───────────────────────────────────────

  Future<void> _fetchMangaList() async {
    setState(() {
      _loadingManga = true;
      _mangaError = null;
      _mangaList = [];
      _selectedManga = null;
      _chapters = [];
      _selectedChapter = null;
      _images = [];
      _readingTestPassed = false;
    });

    try {
      final list = await _parser.fetchMangaList(1);
      setState(() {
        _mangaList = list;
        _loadingManga = false;
      });
    } catch (e) {
      setState(() {
        _mangaError = e.toString();
        _loadingManga = false;
      });
    }
  }

  Future<void> _fetchChapters(Manga manga) async {
    setState(() {
      _selectedManga = manga;
      _loadingChapters = true;
      _chapterError = null;
      _chapters = [];
      _selectedChapter = null;
      _images = [];
    });

    try {
      final chapters = await _parser.fetchChapters(manga.url);
      setState(() {
        _chapters = chapters;
        _loadingChapters = false;
      });
    } catch (e) {
      setState(() {
        _chapterError = e.toString();
        _loadingChapters = false;
      });
    }
  }

  Future<void> _fetchImages(Chapter chapter) async {
    setState(() {
      _selectedChapter = chapter;
      _loadingImages = true;
      _imageError = null;
      _images = [];
    });

    try {
      final images = await _parser.fetchChapterImages(chapter.url);
      setState(() {
        _images = images;
        _loadingImages = false;
      });
    } catch (e) {
      setState(() {
        _imageError = e.toString();
        _loadingImages = false;
      });
    }
  }

  Future<void> _saveSource() async {
    await CustomSourceDB.saveSource(_source);
    setState(() => _saved = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_source.name} saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      // Pop back to the browse screen
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _runAiFix() async {
    if (!NimAiService.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('NVIDIA NIM API key not configured.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _logController.currentAttempt =
        widget.aiService.getAttemptCount(_source.url) + 1;

    final feedback = _feedbackController.text.trim();
    String validationResult = '';
    if (_mangaList.isEmpty) {
      validationResult = '0 manga found';
    } else if (_chapters.isEmpty && _selectedManga != null) {
      validationResult =
          '${_mangaList.length} manga found but 0 chapters for "${_selectedManga!.title}"';
    } else if (_images.isEmpty && _selectedChapter != null) {
      validationResult =
          '${_chapters.length} chapters found but 0 images for "${_selectedChapter!.title}"';
    } else if (!_readingTestPassed) {
      validationResult =
          '${_mangaList.length} manga, ${_chapters.length} chapters, ${_images.length} images — user rejected';
    }

    try {
      final context = AiConversationContext(
        siteUrl: _source.url,
        rawHtml: widget.rawHtml,
        templateGuess: _source.templateType.name,
        attempts: widget.aiService.getContext(_source.url).attempts,
      );

      final selectors = await widget.aiService.refineWithFeedback(
        context,
        feedback,
        validationResult,
        _source.selectors,
        logger: _logController,
      );

      if (selectors.isNotEmpty) {
        _source = _source.copyWith(
          selectors: selectors,
          templateType: TemplateType.aiGenerated,
        );
        _parser = TemplateParser(_source);

        _logController.addAttemptSummary(AiAttemptSummary(
          number: _logController.currentAttempt,
          approach: 'ai-refined',
          result: 'selectors updated',
          success: true,
        ));

        // Re-fetch manga list with new selectors
        await _fetchMangaList();

        setState(() {
          _showAiFeedback = false;
          _feedbackController.clear();
        });
      }
    } catch (e) {
      _logController.markError('AI refinement failed: $e');
      _logController.addAttemptSummary(AiAttemptSummary(
        number: _logController.currentAttempt,
        approach: 'ai-refined',
        result: 'failed: $e',
        success: false,
      ));
    }
  }

  // ── Build ───────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Test: ${_source.name}'),
        elevation: 0,
        actions: [
          if (_readingTestPassed && !_saved)
            TextButton.icon(
              onPressed: _saveSource,
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Save Source'),
              style: TextButton.styleFrom(foregroundColor: Colors.greenAccent),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header info ──
            _buildHeader(theme),
            const SizedBox(height: 16),

            // ── Step 1: Manga List ──
            _buildStep1(),

            // ── Step 2: Chapter List ──
            if (_selectedManga != null) ...[
              const SizedBox(height: 16),
              _buildStep2(),
            ],

            // ── Step 3: Reading Test ──
            if (_selectedChapter != null) ...[
              const SizedBox(height: 16),
              _buildStep3(),
            ],

            // ── AI Feedback section ──
            if (_showAiFeedback) ...[
              const SizedBox(height: 20),
              _buildAiFeedback(),
            ],

            // ── AI Log Panel ──
            if (_logController.entries.isNotEmpty) ...[
              const SizedBox(height: 20),
              AiLogPanel(controller: _logController),
            ],

            const SizedBox(height: 80), // bottom padding for nav bar
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E24),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: _source.logoUrl,
              width: 36,
              height: 36,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) =>
                  const Icon(Icons.public, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _source.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  _source.url
                      .replaceAll('https://', '')
                      .replaceAll('http://', '')
                      .replaceAll(RegExp(r'/$'), ''),
                  style:
                      const TextStyle(color: Colors.blueGrey, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: theme.primaryColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _source.templateType.displayName,
              style: TextStyle(
                color: theme.primaryColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (widget.aiService.getAttemptCount(_source.url) > 0) ...[
            const SizedBox(width: 8),
            Text(
              'AI: ${widget.aiService.getAttemptCount(_source.url)}',
              style: const TextStyle(
                  color: Color(0xFF569CD6), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  // ── Step 1: Manga List ──────────────────────────────────

  Widget _buildStep1() {
    return _buildStepContainer(
      title: 'Step 1: Manga List',
      subtitle: _loadingManga
          ? 'Loading...'
          : _mangaError != null
              ? 'Error'
              : '${_mangaList.length} manga found',
      child: _loadingManga
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : _mangaError != null
              ? _buildErrorWidget(_mangaError!)
              : _mangaList.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No manga found. The selectors may be wrong.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : SizedBox(
                      height: 160,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.all(8),
                        itemCount: _mangaList.length.clamp(0, 15),
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final manga = _mangaList[index];
                          final isSelected =
                              _selectedManga?.url == manga.url;
                          return GestureDetector(
                            onTap: () => _fetchChapters(manga),
                            child: Container(
                              width: 100,
                              decoration: isSelected
                                  ? BoxDecoration(
                                      border: Border.all(
                                          color: Colors.blue, width: 2),
                                      borderRadius:
                                          BorderRadius.circular(10),
                                    )
                                  : null,
                              padding: isSelected
                                  ? const EdgeInsets.all(2)
                                  : null,
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(8),
                                    child: CachedNetworkImage(
                                      imageUrl: manga.coverUrl,
                                      width: 96,
                                      height: 116,
                                      fit: BoxFit.cover,
                                      placeholder: (_, __) => Container(
                                        width: 96,
                                        height: 116,
                                        color: const Color(0xFF2A2A30),
                                        child: const Center(
                                          child: SizedBox(
                                            width: 14,
                                            height: 14,
                                            child:
                                                CircularProgressIndicator(
                                                    strokeWidth: 1.5),
                                          ),
                                        ),
                                      ),
                                      errorWidget: (_, __, ___) =>
                                          Container(
                                        width: 96,
                                        height: 116,
                                        color: const Color(0xFF2A2A30),
                                        child: const Icon(
                                            Icons.broken_image,
                                            color: Colors.grey,
                                            size: 20),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    manga.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }

  // ── Step 2: Chapter List ────────────────────────────────

  Widget _buildStep2() {
    return _buildStepContainer(
      title: 'Step 2: Chapter List',
      subtitle: _loadingChapters
          ? 'Loading...'
          : _chapterError != null
              ? 'Error'
              : '"${_selectedManga?.title}" — ${_chapters.length} chapters',
      child: _loadingChapters
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : _chapterError != null
              ? _buildErrorWidget(_chapterError!)
              : _chapters.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No chapters found.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _chapters.length.clamp(0, 20),
                        itemBuilder: (context, index) {
                          final ch = _chapters[index];
                          final isSelected =
                              _selectedChapter?.url == ch.url;
                          return ListTile(
                            dense: true,
                            tileColor: isSelected
                                ? Colors.blue.withOpacity(0.1)
                                : null,
                            title: Text(
                              ch.title,
                              style: const TextStyle(fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: ch.releaseDate != null
                                ? Text(
                                    ch.releaseDate!,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey),
                                  )
                                : null,
                            trailing: const Icon(Icons.chevron_right,
                                size: 18, color: Colors.grey),
                            onTap: () => _fetchImages(ch),
                          );
                        },
                      ),
                    ),
    );
  }

  // ── Step 3: Reading Test ────────────────────────────────

  Widget _buildStep3() {
    return _buildStepContainer(
      title: 'Step 3: Reading Test',
      subtitle: _loadingImages
          ? 'Loading...'
          : _imageError != null
              ? 'Error'
              : '${_selectedChapter?.title} — ${_images.length} images',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loadingImages)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_imageError != null)
            _buildErrorWidget(_imageError!)
          else if (_images.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No images found.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.all(8),
                itemCount: _images.length.clamp(0, 10),
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: CachedNetworkImage(
                      imageUrl: _images[index],
                      fit: BoxFit.fitWidth,
                      placeholder: (_, __) => Container(
                        height: 200,
                        color: const Color(0xFF2A2A30),
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        height: 100,
                        color: const Color(0xFF2A2A30),
                        child: const Center(
                          child: Icon(Icons.broken_image,
                              color: Colors.grey, size: 32),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── Confirmation buttons ──
            if (!_readingTestPassed) ...[
              const SizedBox(height: 12),
              const Text(
                'Are these actual manga pages?',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() => _readingTestPassed = true);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Reading test passed! You can now save this source.'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      },
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Yes, looks correct'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.withOpacity(0.2),
                        foregroundColor: Colors.greenAccent,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() => _showAiFeedback = true);
                      },
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('No, these are wrong'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.withOpacity(0.2),
                        foregroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Reading test passed!',
                      style: TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ── AI Feedback ─────────────────────────────────────────

  Widget _buildAiFeedback() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E24),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Report Issue to AI',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Color(0xFF569CD6),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'What\'s wrong? (describe what you see):',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _feedbackController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText:
                  'The images are website banners, not manga pages...',
              hintStyle: TextStyle(color: Colors.grey[600]),
              filled: true,
              fillColor: const Color(0xFF0D1117),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: NimAiService.isConfigured ? _runAiFix : null,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Send to AI for Fix'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF569CD6).withOpacity(0.2),
                foregroundColor: const Color(0xFF569CD6),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          if (widget.aiService.getAttemptCount(_source.url) >=
              NimAiService.maxAttempts) ...[
            const SizedBox(height: 8),
            const Text(
              'Maximum AI attempts reached. Try a different URL or add selectors manually.',
              style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  // ── Shared widgets ──────────────────────────────────────

  Widget _buildStepContainer({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                Text(
                  subtitle,
                  style: const TextStyle(
                      color: Colors.blueGrey, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }

  Widget _buildErrorWidget(String error) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          error,
          style: const TextStyle(color: Colors.redAccent, fontSize: 12),
        ),
      ),
    );
  }
}
