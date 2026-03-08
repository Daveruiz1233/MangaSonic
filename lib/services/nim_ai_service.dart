import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:manga_sonic/ui/widgets/ai_log_panel.dart';

// ── Data classes ─────────────────────────────────────────────

/// A single AI attempt — what it tried and what happened.
class AiAttempt {
  final String approach;
  final Map<String, String> selectors;
  final String? userFeedback;
  final String? validationResult;
  final DateTime timestamp;

  AiAttempt({
    required this.approach,
    required this.selectors,
    this.userFeedback,
    this.validationResult,
    required this.timestamp,
  });
}

/// Full conversation context for a source — grows with each retry.
class AiConversationContext {
  final String siteUrl;
  final String rawHtml;
  final String templateGuess;
  final List<AiAttempt> attempts;

  AiConversationContext({
    required this.siteUrl,
    required this.rawHtml,
    required this.templateGuess,
    List<AiAttempt>? attempts,
  }) : attempts = attempts ?? [];

  AiConversationContext copyWith({
    String? siteUrl,
    String? rawHtml,
    String? templateGuess,
    List<AiAttempt>? attempts,
  }) {
    return AiConversationContext(
      siteUrl: siteUrl ?? this.siteUrl,
      rawHtml: rawHtml ?? this.rawHtml,
      templateGuess: templateGuess ?? this.templateGuess,
      attempts: attempts ?? this.attempts,
    );
  }
}

// ── NIM AI Service ──────────────────────────────────────────

class NimAiService {
  static const String _settingsBox = 'nim_settings';
  static const String _apiKeyField = 'api_key';
  static const int maxAttempts = 5;

  // Per-source conversation contexts
  final Map<String, AiConversationContext> _contexts = {};

  static Future<void> init() async {
    await Hive.openBox(_settingsBox);
  }

  // ── API Key management ──────────────────────────────────

  static String? getApiKey() {
    final box = Hive.box(_settingsBox);
    return box.get(_apiKeyField) as String?;
  }

  static Future<void> setApiKey(String key) async {
    final box = Hive.box(_settingsBox);
    await box.put(_apiKeyField, key);
  }

  static bool get isConfigured {
    final key = getApiKey();
    return key != null && key.isNotEmpty;
  }

  // ── Context management ──────────────────────────────────

  AiConversationContext getContext(String siteUrl) {
    return _contexts[siteUrl] ??
        AiConversationContext(
          siteUrl: siteUrl,
          rawHtml: '',
          templateGuess: 'unknown',
        );
  }

  void setContext(String siteUrl, AiConversationContext context) {
    _contexts[siteUrl] = context;
  }

  int getAttemptCount(String siteUrl) {
    return _contexts[siteUrl]?.attempts.length ?? 0;
  }

  void resetContext(String siteUrl) {
    _contexts.remove(siteUrl);
  }

  // ── Core AI methods ─────────────────────────────────────

  /// First AI attempt — no history yet.
  Future<Map<String, String>> analyzePageForSelectors(
    AiConversationContext context, {
    AiLogController? logger,
  }) async {
    setContext(context.siteUrl, context);

    logger?.logWorking('Preparing HTML payload...');
    final truncatedHtml = _truncateHtml(context.rawHtml);
    final originalSize = (context.rawHtml.length / 1024).toStringAsFixed(1);
    final truncatedSize = (truncatedHtml.length / 1024).toStringAsFixed(1);
    logger?.markSuccess(
        'Stripped scripts & styles (${originalSize}KB → ${truncatedSize}KB)');

    logger?.logWorking(
        'Built conversation context (${context.attempts.length} prior attempts)');
    logger?.markSuccess('Built conversation context');

    logger?.logWorking('Sending to NVIDIA NIM...');
    final stopwatch = Stopwatch()..start();

    final prompt = _buildPrompt(context, truncatedHtml);
    final responseText = await _callNim(prompt);
    final elapsed = (stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1);
    logger?.markSuccess('Response received (${elapsed}s)');

    logger?.logWorking('Parsing selector JSON...');
    final selectors = _parseSelectorsFromResponse(responseText);
    logger?.markSuccess('Extracted ${selectors.length} selectors');

    return selectors;
  }

  /// Refine with user feedback — adds attempt to history, sends full context.
  Future<Map<String, String>> refineWithFeedback(
    AiConversationContext context,
    String? userFeedback,
    String? validationResult,
    Map<String, String> previousSelectors, {
    AiLogController? logger,
  }) async {
    // Record the previous attempt
    final attempt = AiAttempt(
      approach: 'Attempt #${context.attempts.length + 1}',
      selectors: previousSelectors,
      userFeedback: userFeedback,
      validationResult: validationResult,
      timestamp: DateTime.now(),
    );
    context.attempts.add(attempt);
    setContext(context.siteUrl, context);

    logger?.logWorking('Preparing HTML payload...');
    final truncatedHtml = _truncateHtml(context.rawHtml);
    final originalSize = (context.rawHtml.length / 1024).toStringAsFixed(1);
    final truncatedSize = (truncatedHtml.length / 1024).toStringAsFixed(1);
    logger?.markSuccess(
        'Stripped scripts & styles (${originalSize}KB → ${truncatedSize}KB)');

    logger?.logWorking(
        'Built conversation context (${context.attempts.length} prior attempts)');
    logger?.markSuccess('Built conversation context');

    logger?.logWorking('Sending to NVIDIA NIM...');
    final stopwatch = Stopwatch()..start();

    final prompt = _buildPrompt(context, truncatedHtml);
    final responseText = await _callNim(prompt);
    final elapsed = (stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1);
    logger?.markSuccess('Response received (${elapsed}s)');

    logger?.logWorking('Parsing selector JSON...');
    final selectors = _parseSelectorsFromResponse(responseText);
    logger?.markSuccess('Extracted ${selectors.length} selectors');

    return selectors;
  }

  // ── Prompt construction ─────────────────────────────────

  String _buildPrompt(AiConversationContext context, String truncatedHtml) {
    final buffer = StringBuffer();

    buffer.writeln(
        'SYSTEM: You are a manga website parser engineer. Given a page\'s HTML,');
    buffer.writeln(
        'produce CSS selectors that extract manga data.');
    buffer.writeln();
    buffer.writeln('CONTEXT:');
    buffer.writeln('- Site URL: ${context.siteUrl}');
    buffer.writeln(
        '- Auto-detect result: ${context.templateGuess} (failed / low confidence)');
    buffer.writeln('- Previous attempts: ${context.attempts.length}');
    buffer.writeln();

    // Include full history of previous attempts
    for (int i = 0; i < context.attempts.length; i++) {
      final a = context.attempts[i];
      buffer.writeln('ATTEMPT #${i + 1}:');
      buffer.writeln('  Approach: ${a.approach}');
      buffer.writeln(
          '  Selectors produced: ${jsonEncode(a.selectors)}');
      if (a.userFeedback != null && a.userFeedback!.isNotEmpty) {
        buffer.writeln('  User feedback: "${a.userFeedback}"');
      }
      if (a.validationResult != null && a.validationResult!.isNotEmpty) {
        buffer.writeln('  Validation: ${a.validationResult}');
      }
      buffer.writeln('  → DO NOT repeat this approach.');
      buffer.writeln();
    }

    buffer.writeln(
        'INSTRUCTION: Try a DIFFERENT approach than the ones listed above.');
    buffer.writeln(
        'Analyze the HTML structure below and produce new CSS selectors.');
    buffer.writeln(
        'Return ONLY valid JSON with the selector map. The JSON should have these keys:');
    buffer.writeln(
        '  listUrl, searchUrl, mangaList, mangaLink, mangaImage,');
    buffer.writeln(
        '  chapterList, chapterLink, chapterImages,');
    buffer.writeln('  description, author, status, genres');
    buffer.writeln();
    buffer.writeln(
        'For listUrl and searchUrl, use {page} and {query} as placeholders.');
    buffer.writeln();
    buffer.writeln('HTML (truncated):');
    buffer.writeln(truncatedHtml);

    return buffer.toString();
  }

  // ── NIM API call ────────────────────────────────────────

  Future<String> _callNim(String prompt) async {
    final apiKey = getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('NVIDIA NIM API key not configured');
    }

    final response = await http.post(
      Uri.parse(
          'https://integrate.api.nvidia.com/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'meta/llama-3.1-70b-instruct',
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
        'temperature': 0.3,
        'max_tokens': 2048,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
          'NIM API error ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body);
    return data['choices'][0]['message']['content'] as String;
  }

  // ── HTML truncation ─────────────────────────────────────

  String _truncateHtml(String html) {
    // Remove <script> and <style> blocks to reduce size
    var cleaned = html
        .replaceAll(RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Truncate to ~30KB to fit in LLM context
    const maxLength = 30000;
    if (cleaned.length > maxLength) {
      cleaned = cleaned.substring(0, maxLength);
    }
    return cleaned;
  }

  // ── Response parsing ────────────────────────────────────

  Map<String, String> _parseSelectorsFromResponse(String response) {
    try {
      // Try to find JSON in the response
      final jsonMatch =
          RegExp(r'\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}').firstMatch(response);
      if (jsonMatch != null) {
        final jsonStr = jsonMatch.group(0)!;
        final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
        return parsed.map(
            (key, value) => MapEntry(key, value?.toString() ?? ''));
      }
    } catch (e) {
      debugPrint('NimAiService: Failed to parse JSON from response: $e');
    }

    // Fallback: try to parse the entire response as JSON
    try {
      final parsed = jsonDecode(response) as Map<String, dynamic>;
      return parsed
          .map((key, value) => MapEntry(key, value?.toString() ?? ''));
    } catch (e) {
      debugPrint('NimAiService: Fallback JSON parse also failed: $e');
    }

    return {};
  }
}
