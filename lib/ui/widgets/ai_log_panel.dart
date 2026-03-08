import 'dart:async';
import 'package:flutter/material.dart';

// ── Log level ───────────────────────────────────────────────

enum AiLogLevel { info, success, error, working }

// ── Log entry ───────────────────────────────────────────────

class AiLogEntry {
  final String message;
  AiLogLevel level;
  final DateTime timestamp;

  AiLogEntry({
    required this.message,
    required this.level,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

// ── Attempt summary for history section ─────────────────────

class AiAttemptSummary {
  final int number;
  final String approach;
  final String result;
  final bool success;

  AiAttemptSummary({
    required this.number,
    required this.approach,
    required this.result,
    required this.success,
  });
}

// ── Controller ──────────────────────────────────────────────

class AiLogController extends ChangeNotifier {
  final List<AiLogEntry> entries = [];
  int currentAttempt = 0;
  int maxAttempts = 5;
  final List<AiAttemptSummary> attemptHistory = [];

  void log(String message, {AiLogLevel level = AiLogLevel.info}) {
    entries.add(AiLogEntry(message: message, level: level));
    notifyListeners();
  }

  void logWorking(String message) {
    entries.add(AiLogEntry(message: message, level: AiLogLevel.working));
    notifyListeners();
  }

  void markSuccess(String message) {
    // Find the last working entry and convert it
    for (int i = entries.length - 1; i >= 0; i--) {
      if (entries[i].level == AiLogLevel.working) {
        entries[i].level = AiLogLevel.success;
        entries[i] = AiLogEntry(
          message: message,
          level: AiLogLevel.success,
          timestamp: entries[i].timestamp,
        );
        break;
      }
    }
    notifyListeners();
  }

  void markError(String message) {
    // Find the last working entry and convert it
    for (int i = entries.length - 1; i >= 0; i--) {
      if (entries[i].level == AiLogLevel.working) {
        entries[i] = AiLogEntry(
          message: message,
          level: AiLogLevel.error,
          timestamp: entries[i].timestamp,
        );
        break;
      }
    }
    notifyListeners();
  }

  void addAttemptSummary(AiAttemptSummary summary) {
    attemptHistory.add(summary);
    notifyListeners();
  }

  void clear() {
    entries.clear();
    attemptHistory.clear();
    currentAttempt = 0;
    notifyListeners();
  }
}

// ── Braille spinner ─────────────────────────────────────────

const _spinnerFrames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];

// ── Widget ──────────────────────────────────────────────────

class AiLogPanel extends StatefulWidget {
  final AiLogController controller;
  final bool initiallyExpanded;

  const AiLogPanel({
    super.key,
    required this.controller,
    this.initiallyExpanded = true,
  });

  @override
  State<AiLogPanel> createState() => _AiLogPanelState();
}

class _AiLogPanelState extends State<AiLogPanel> {
  bool _expanded = true;
  final ScrollController _scrollController = ScrollController();
  Timer? _spinnerTimer;
  int _spinnerIndex = 0;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    widget.controller.addListener(_onLog);

    // Braille spinner animation timer
    _spinnerTimer = Timer.periodic(
      const Duration(milliseconds: 80),
      (_) {
        if (mounted &&
            widget.controller.entries
                .any((e) => e.level == AiLogLevel.working)) {
          setState(() {
            _spinnerIndex = (_spinnerIndex + 1) % _spinnerFrames.length;
          });
        }
      },
    );
  }

  void _onLog() {
    if (mounted) {
      setState(() {});
      // Auto-scroll to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onLog);
    _spinnerTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header bar (tap to expand/collapse) ──
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: _expanded
                    ? const BorderRadius.vertical(top: Radius.circular(12))
                    : BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Text(
                    '── AI Engine ',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Color(0xFF8B949E),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  if (controller.currentAttempt > 0)
                    Text(
                      'attempt ${controller.currentAttempt}/${controller.maxAttempts}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Color(0xFF6A737D),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_up,
                    color: const Color(0xFF6A737D),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),

          // ── Collapsed: show last log line ──
          if (!_expanded && controller.entries.isNotEmpty)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: _buildLogLine(controller.entries.last),
            ),

          // ── Expanded: full log + history ──
          if (_expanded) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.builder(
                controller: _scrollController,
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                itemCount: controller.entries.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1.5),
                    child: _buildLogLine(controller.entries[index]),
                  );
                },
              ),
            ),

            // ── Attempt history section ──
            if (controller.attemptHistory.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Container(
                  height: 1,
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '── Previous attempts ──',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Color(0xFF6A737D),
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...controller.attemptHistory.map(_buildAttemptLine),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _buildLogLine(AiLogEntry entry) {
    String prefix;
    Color prefixColor;
    Color messageColor;

    switch (entry.level) {
      case AiLogLevel.working:
        prefix = _spinnerFrames[_spinnerIndex];
        prefixColor = const Color(0xFF569CD6); // cyan/blue
        messageColor = const Color(0xFFC9D1D9);
        break;
      case AiLogLevel.success:
        prefix = '✓';
        prefixColor = const Color(0xFF4EC9B0); // green
        messageColor = const Color(0xFFC9D1D9);
        break;
      case AiLogLevel.error:
        prefix = '✗';
        prefixColor = const Color(0xFFE06C75); // red
        messageColor = const Color(0xFFE06C75);
        break;
      case AiLogLevel.info:
        prefix = '·';
        prefixColor = const Color(0xFF6A737D);
        messageColor = const Color(0xFF8B949E);
        break;
    }

    final time =
        '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
        '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
        '${entry.timestamp.second.toString().padLeft(2, '0')}';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          prefix,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: prefixColor,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          time,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: Color(0xFF6A737D),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            entry.message,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: messageColor,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAttemptLine(AiAttemptSummary attempt) {
    final statusColor = attempt.success
        ? const Color(0xFF4EC9B0)
        : const Color(0xFFE06C75);
    final statusText = attempt.success ? 'OK' : 'FAILED';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Text(
            '#${attempt.number}',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Color(0xFF8B949E),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${attempt.approach}  → ${attempt.result}',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Color(0xFF6A737D),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: statusColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
