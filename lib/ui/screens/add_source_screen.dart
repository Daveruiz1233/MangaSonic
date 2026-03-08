import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:manga_sonic/data/models/custom_source_model.dart';
import 'package:manga_sonic/parser/template_parser.dart';
import 'package:manga_sonic/services/nim_ai_service.dart';
import 'package:manga_sonic/utils/site_template_detector.dart';
import 'package:manga_sonic/ui/widgets/ai_log_panel.dart';
import 'package:manga_sonic/ui/screens/test_source_screen.dart';

/// Screen states for the Add Source flow.
enum _ScreenState {
  input,
  detecting,
  preview,
  aiFallback,
  aiPreview,
}

class AddSourceScreen extends StatefulWidget {
  const AddSourceScreen({super.key});

  @override
  State<AddSourceScreen> createState() => _AddSourceScreenState();
}

class _AddSourceScreenState extends State<AddSourceScreen> {
  final _urlController = TextEditingController();
  final _feedbackController = TextEditingController();
  final _detector = SiteTemplateDetector();
  final _aiService = NimAiService();
  final _logController = AiLogController();

  _ScreenState _state = _ScreenState.input;
  DetectionResult? _detectionResult;
  Map<String, String> _currentSelectors = {};
  String _statusMessage = '';
  String? _errorMessage;
  List<SampleManga> _sampleManga = [];
  TemplateType _templateType = TemplateType.generic;
  String _rawHtml = '';

  @override
  void dispose() {
    _urlController.dispose();
    _feedbackController.dispose();
    _detector.dispose();
    _logController.dispose();
    super.dispose();
  }

  // ── Actions ─────────────────────────────────────────────

  Future<void> _startDetection() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    // Basic URL validation
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      _urlController.text = 'https://$url';
    }

    setState(() {
      _state = _ScreenState.detecting;
      _statusMessage = 'Fetching homepage...';
      _errorMessage = null;
    });

    try {
      setState(() => _statusMessage = 'Fetching homepage...');
      final result = await _detector.detect(_urlController.text.trim());
      _detectionResult = result;
      _rawHtml = result.rawHtml ?? '';

      setState(() => _statusMessage = 'Analyzing structure...');
      await Future.delayed(const Duration(milliseconds: 300));

      if (result.templateType != TemplateType.generic &&
          result.confidence >= 0.5) {
        // Auto-detection succeeded
        _templateType = result.templateType;
        _currentSelectors = result.extractedSelectors;
        _sampleManga = result.sampleManga;

        setState(() {
          _state = _ScreenState.preview;
          _statusMessage =
              '✓ Detected: ${_templateType.displayName}\n'
              'Found ${_sampleManga.length} manga on frontpage';
        });
      } else {
        // Auto-detection failed → check if AI is available
        if (NimAiService.isConfigured) {
          setState(() {
            _state = _ScreenState.aiFallback;
            _statusMessage =
                'Could not auto-detect site template.\n'
                'AI analysis available.';
          });
        } else {
          setState(() {
            _state = _ScreenState.aiFallback;
            _statusMessage =
                'Could not auto-detect site template.\n'
                'Configure NVIDIA NIM API key in Settings to enable AI analysis.';
          });
        }
      }
    } catch (e) {
      setState(() {
        _state = _ScreenState.input;
        _errorMessage = 'Failed to fetch site: $e';
      });
    }
  }

  Future<void> _runAiAnalysis({String? feedback}) async {
    if (!NimAiService.isConfigured) {
      setState(() {
        _errorMessage =
            'NVIDIA NIM API key not configured. Go to Settings to add it.';
      });
      return;
    }

    setState(() {
      _state = _ScreenState.detecting;
      _statusMessage = 'Running AI analysis...';
      _errorMessage = null;
    });

    _logController.currentAttempt = _aiService.getAttemptCount(
            _urlController.text.trim()) +
        1;

    try {
      final context = AiConversationContext(
        siteUrl: _urlController.text.trim(),
        rawHtml: _rawHtml,
        templateGuess: _detectionResult?.templateType.name ?? 'unknown',
        attempts: _aiService.getContext(_urlController.text.trim()).attempts,
      );

      Map<String, String> selectors;
      if (feedback != null && feedback.isNotEmpty) {
        selectors = await _aiService.refineWithFeedback(
          context,
          feedback,
          _currentSelectors.isEmpty
              ? '0 manga found'
              : '${_sampleManga.length} manga found but user rejected',
          _currentSelectors,
          logger: _logController,
        );
      } else {
        selectors = await _aiService.analyzePageForSelectors(
          context,
          logger: _logController,
        );
      }

      if (selectors.isNotEmpty) {
        _currentSelectors = selectors;
        _templateType = TemplateType.aiGenerated;

        // Try to validate by fetching some sample manga
        _logController.logWorking('Validating: testing selectors...');

        // Build a temporary source to test
        final tempSource = _buildTemporarySource();
        try {
          final parser =
              _createTemplateParser(tempSource);
          final manga = await parser.fetchMangaList(1);
          _sampleManga = manga
              .take(6)
              .map((m) => SampleManga(
                    title: m.title,
                    url: m.url,
                    coverUrl: m.coverUrl,
                  ))
              .toList();
          _logController.markSuccess(
              'Found ${_sampleManga.length} manga titles');

          _logController.addAttemptSummary(AiAttemptSummary(
            number: _logController.currentAttempt,
            approach: 'ai-selectors',
            result:
                '${_sampleManga.length} manga found',
            success: _sampleManga.isNotEmpty,
          ));
        } catch (e) {
          _logController.markError('Validation failed: $e');
          _sampleManga = [];
          _logController.addAttemptSummary(AiAttemptSummary(
            number: _logController.currentAttempt,
            approach: 'ai-selectors',
            result: 'validation failed',
            success: false,
          ));
        }

        setState(() {
          _state = _ScreenState.aiPreview;
          _statusMessage = _sampleManga.isNotEmpty
              ? 'AI generated ${selectors.length} selectors. Found ${_sampleManga.length} manga.'
              : 'AI generated selectors but could not find manga. Try providing feedback.';
        });
      } else {
        setState(() {
          _state = _ScreenState.aiFallback;
          _errorMessage =
              'AI could not generate valid selectors. Try providing more details.';
        });
      }
    } catch (e) {
      setState(() {
        _state = _ScreenState.aiFallback;
        _errorMessage = 'AI analysis failed: $e';
      });
    }
  }

  CustomSourceModel _buildTemporarySource() {
    final url = _urlController.text.trim();
    final uri = Uri.parse(url);
    final domain = uri.host.replaceAll(RegExp(r'^www\.'), '');
    final sourceId = CustomSourceModel.deriveSourceId(domain);

    return CustomSourceModel(
      sourceId: sourceId,
      name: domain.split('.').first[0].toUpperCase() +
          domain.split('.').first.substring(1),
      url: url.endsWith('/') ? url : '$url/',
      logoUrl: CustomSourceModel.faviconUrl(domain),
      templateType: _templateType,
      selectors: _currentSelectors,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  TemplateParser _createTemplateParser(CustomSourceModel source) {
    return TemplateParser(source);
  }

  void _navigateToTest() {
    final source = _buildTemporarySource();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TestSourceScreen(
          source: source,
          rawHtml: _rawHtml,
          aiService: _aiService,
        ),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Source'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildUrlInput(),
            const SizedBox(height: 16),
            if (_errorMessage != null) _buildError(),
            if (_state == _ScreenState.detecting) _buildDetecting(),
            if (_state == _ScreenState.preview) _buildPreview(),
            if (_state == _ScreenState.aiFallback) _buildAiFallback(),
            if (_state == _ScreenState.aiPreview) _buildAiPreview(),
            if (_logController.entries.isNotEmpty) ...[
              const SizedBox(height: 20),
              AiLogPanel(controller: _logController),
            ],
          ],
        ),
      ),
    );
  }

  // ── Sub-builders ────────────────────────────────────────

  Widget _buildUrlInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Paste the website URL:',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  hintText: 'https://mangakakalot.com',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: const Color(0xFF1E1E24),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () async {
                final data = await Clipboard.getData('text/plain');
                if (data?.text != null) {
                  _urlController.text = data!.text!;
                }
              },
              icon: const Icon(Icons.paste, color: Colors.grey),
              tooltip: 'Paste',
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed:
                _state == _ScreenState.detecting ? null : _startDetection,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Detect & Add',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Text(
        _errorMessage!,
        style: const TextStyle(color: Colors.redAccent, fontSize: 13),
      ),
    );
  }

  Widget _buildDetecting() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E24),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child:
                CircularProgressIndicator(strokeWidth: 2, color: Colors.blue),
          ),
          const SizedBox(height: 12),
          Text(
            _statusMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        // Status
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _statusMessage,
                  style:
                      const TextStyle(color: Colors.greenAccent, fontSize: 13),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _templateType.displayName,
                  style: TextStyle(
                    color: Theme.of(context).primaryColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Preview grid
        if (_sampleManga.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'PREVIEW',
            style: TextStyle(
              color: Colors.blueGrey,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _sampleManga.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) =>
                  _buildSampleCard(_sampleManga[index]),
            ),
          ),
        ],

        // Action buttons
        const SizedBox(height: 20),
        const Text(
          'Does this look right?',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _navigateToTest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.withOpacity(0.2),
                  foregroundColor: Colors.greenAccent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Yes, Test Source'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  setState(() => _state = _ScreenState.aiFallback);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.withOpacity(0.2),
                  foregroundColor: Colors.orangeAccent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('No, Try AI Fix'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAiFallback() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E24),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _statusMessage,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 16),
          const Text(
            'What\'s wrong? (optional):',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _feedbackController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'The titles are wrong, images are ads, etc...',
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
              onPressed: NimAiService.isConfigured
                  ? () =>
                      _runAiAnalysis(feedback: _feedbackController.text.trim())
                  : null,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Retry with AI'),
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
        ],
      ),
    );
  }

  Widget _buildAiPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF569CD6).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: const Color(0xFF569CD6).withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome,
                  color: Color(0xFF569CD6), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _statusMessage,
                  style: const TextStyle(
                      color: Color(0xFF9ECBFF), fontSize: 13),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF569CD6).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'AI Generated',
                  style: TextStyle(
                    color: Color(0xFF569CD6),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Sample manga grid
        if (_sampleManga.isNotEmpty) ...[
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _sampleManga.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) =>
                  _buildSampleCard(_sampleManga[index]),
            ),
          ),
        ],

        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed:
                    _sampleManga.isNotEmpty ? _navigateToTest : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.withOpacity(0.2),
                  foregroundColor: Colors.greenAccent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Yes, Test Source'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _state = _ScreenState.aiFallback;
                    _feedbackController.clear();
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.withOpacity(0.2),
                  foregroundColor: Colors.orangeAccent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('No, Try AI Fix'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSampleCard(SampleManga manga) {
    return SizedBox(
      width: 100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: manga.coverUrl,
              width: 100,
              height: 120,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                width: 100,
                height: 120,
                color: const Color(0xFF2A2A30),
                child: const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                ),
              ),
              errorWidget: (_, __, ___) => Container(
                width: 100,
                height: 120,
                color: const Color(0xFF2A2A30),
                child: const Icon(Icons.broken_image,
                    color: Colors.grey, size: 24),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            manga.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
