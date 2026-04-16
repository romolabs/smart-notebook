import '../models/notebook_models.dart';

abstract class EnhancementEngine {
  Future<EnhancementSnapshot> process(EnhancementRequest request);
}

class FormatterProcessorResult {
  const FormatterProcessorResult({
    required this.enhancedText,
    required this.changes,
    required this.status,
  });

  final String enhancedText;
  final List<EnhancementChange> changes;
  final ProcessorStatus status;
}

class VerifierProcessorResult {
  const VerifierProcessorResult({
    required this.flags,
    required this.changes,
    required this.status,
  });

  final List<VerificationFlag> flags;
  final List<EnhancementChange> changes;
  final ProcessorStatus status;
}

abstract class LocalModelAdapter {
  const LocalModelAdapter();

  Future<FormatterProcessorResult> runFormatter({
    required EnhancementRequest request,
  });

  Future<VerifierProcessorResult> runVerifier({
    required EnhancementRequest request,
    required String enhancedText,
  });
}

class MockEnhancementEngine implements EnhancementEngine {
  const MockEnhancementEngine({
    this.localModelAdapter = const UnavailableLocalModelAdapter(),
  });

  final LocalModelAdapter localModelAdapter;

  @override
  Future<EnhancementSnapshot> process(EnhancementRequest request) async {
    final trimmed = request.rawContent.trim();
    if (trimmed.isEmpty) {
      return _emptySnapshot();
    }

    var working = trimmed;
    final changes = <EnhancementChange>[];
    final flags = <VerificationFlag>[];
    final processorStatuses = <ProcessorStatus>[];

    if (request.toggles.spelling ||
        request.toggles.formatting ||
        request.toggles.clarity) {
      final baselineChanges = <EnhancementChange>[];
      final baseline = _applyFormatterFallback(
        working,
        baselineChanges,
        request.toggles,
      );
      final formatterResult = request.modelMode == ModelMode.localFast
          ? await localModelAdapter.runFormatter(request: request)
          : _cloudNotReadyFormatter();

      if (formatterResult.status.state == ProcessorState.completed &&
          _shouldUseModelFormatter(
            rawContent: request.rawContent,
            baseline: baseline,
            candidate: formatterResult.enhancedText,
          )) {
        working = formatterResult.enhancedText;
        changes.addAll(
          formatterResult.changes.isEmpty
              ? baselineChanges
              : formatterResult.changes,
        );
        processorStatuses.add(
          ProcessorStatus(
            kind: ProcessorKind.formatter,
            state: ProcessorState.completed,
            label: 'Formatter',
            detail:
                '${formatterResult.status.detail} Accepted after structural quality check.',
          ),
        );
      } else {
        working = baseline;
        changes.addAll(baselineChanges);
        processorStatuses.add(
          ProcessorStatus(
            kind: ProcessorKind.formatter,
            state: request.modelMode == ModelMode.localFast
                ? ProcessorState.completed
                : formatterResult.status.state,
            label: 'Formatter',
            detail: request.modelMode == ModelMode.localFast
                ? 'Used deterministic structure-preserving formatter because model output was weaker.'
                : formatterResult.status.detail,
          ),
        );
      }
    } else {
      processorStatuses.add(
        const ProcessorStatus(
          kind: ProcessorKind.formatter,
          state: ProcessorState.skipped,
          label: 'Formatter',
          detail: 'Formatter processors are turned off.',
        ),
      );
    }

    if (request.toggles.verification) {
      if (request.modelMode == ModelMode.localFast) {
        final verificationFlags = _detectVerificationFlags(request.rawContent);
        if (verificationFlags.isNotEmpty) {
          flags.addAll(verificationFlags);
          changes.add(
            const EnhancementChange(
              type: ChangeType.verification,
              label: 'Verification hints',
              description:
                  'Flagged specific claims that may deserve a source check before sharing.',
            ),
          );
        }
        processorStatuses.add(
          const ProcessorStatus(
            kind: ProcessorKind.verifier,
            state: ProcessorState.completed,
            label: 'Verifier',
            detail:
                'Used conservative local verification rules to avoid speculative model warnings.',
          ),
        );
      } else {
        final verifierResult = _cloudNotReadyVerifier();
        final verificationFlags = _detectVerificationFlags(request.rawContent);
        if (verificationFlags.isNotEmpty) {
          flags.addAll(verificationFlags);
          changes.add(
            const EnhancementChange(
              type: ChangeType.verification,
              label: 'Verification hints',
              description:
                  'Flagged specific claims that may deserve a source check before sharing.',
            ),
          );
        }
        processorStatuses.add(_fallbackStatus(verifierResult.status));
      }
    } else {
      processorStatuses.add(
        const ProcessorStatus(
          kind: ProcessorKind.verifier,
          state: ProcessorState.skipped,
          label: 'Verifier',
          detail: 'Verification is turned off.',
        ),
      );
    }

    return EnhancementSnapshot(
      enhancedContent: working,
      summary: _buildSummary(trimmed),
      changes: changes,
      flags: flags,
      processorStatuses: processorStatuses,
    );
  }

  EnhancementSnapshot processSync(EnhancementRequest request) {
    final trimmed = request.rawContent.trim();
    if (trimmed.isEmpty) {
      return _emptySnapshot();
    }

    final changes = <EnhancementChange>[];
    final working = _applyFormatterFallback(trimmed, changes, request.toggles);
    final flags = request.toggles.verification
        ? _detectVerificationFlags(request.rawContent)
        : const <VerificationFlag>[];
    final statuses = <ProcessorStatus>[
      if (request.toggles.spelling ||
          request.toggles.formatting ||
          request.toggles.clarity)
        const ProcessorStatus(
          kind: ProcessorKind.formatter,
          state: ProcessorState.unavailable,
          label: 'Formatter',
          detail: 'Seed snapshot used deterministic formatter fallback.',
        )
      else
        const ProcessorStatus(
          kind: ProcessorKind.formatter,
          state: ProcessorState.skipped,
          label: 'Formatter',
          detail: 'Formatter processors are turned off.',
        ),
      if (request.toggles.verification)
        const ProcessorStatus(
          kind: ProcessorKind.verifier,
          state: ProcessorState.unavailable,
          label: 'Verifier',
          detail: 'Seed snapshot used conservative verification fallback.',
        )
      else
        const ProcessorStatus(
          kind: ProcessorKind.verifier,
          state: ProcessorState.skipped,
          label: 'Verifier',
          detail: 'Verification is turned off.',
        ),
    ];

    if (flags.isNotEmpty) {
      changes.add(
        const EnhancementChange(
          type: ChangeType.verification,
          label: 'Verification hints',
          description:
              'Flagged specific claims that may deserve a source check before sharing.',
        ),
      );
    }

    return EnhancementSnapshot(
      enhancedContent: working,
      summary: _buildSummary(trimmed),
      changes: changes,
      flags: flags,
      processorStatuses: statuses,
    );
  }

  EnhancementSnapshot _emptySnapshot() {
    return const EnhancementSnapshot(
      enhancedContent: 'Your enhanced note will appear here as you type.',
      summary:
          'Start writing in the raw pane to see structure, cleanup, and verification hints.',
      changes: [],
      flags: [],
      processorStatuses: [
        ProcessorStatus(
          kind: ProcessorKind.formatter,
          state: ProcessorState.skipped,
          label: 'Formatter',
          detail: 'Waiting for note content.',
        ),
        ProcessorStatus(
          kind: ProcessorKind.verifier,
          state: ProcessorState.skipped,
          label: 'Verifier',
          detail: 'Waiting for note content.',
        ),
      ],
    );
  }

  FormatterProcessorResult _cloudNotReadyFormatter() {
    return const FormatterProcessorResult(
      enhancedText: '',
      changes: [],
      status: ProcessorStatus(
        kind: ProcessorKind.formatter,
        state: ProcessorState.unavailable,
        label: 'Formatter',
        detail: 'Cloud formatter is not wired yet, using local fallback.',
      ),
    );
  }

  VerifierProcessorResult _cloudNotReadyVerifier() {
    return const VerifierProcessorResult(
      flags: [],
      changes: [],
      status: ProcessorStatus(
        kind: ProcessorKind.verifier,
        state: ProcessorState.unavailable,
        label: 'Verifier',
        detail: 'Cloud verifier is not wired yet, using local fallback.',
      ),
    );
  }

  ProcessorStatus _fallbackStatus(ProcessorStatus status) {
    return ProcessorStatus(
      kind: status.kind,
      state: status.state,
      label: status.label,
      detail: status.detail,
    );
  }

  bool _shouldUseModelFormatter({
    required String rawContent,
    required String baseline,
    required String candidate,
  }) {
    final normalizedCandidate = candidate.trim();
    if (normalizedCandidate.isEmpty) {
      return false;
    }

    final rawLines = _meaningfulLines(rawContent);
    final baselineLines = _meaningfulLines(baseline);
    final candidateLines = _meaningfulLines(normalizedCandidate);
    final hasStructuredRaw = rawLines.length >= 3;

    if (hasStructuredRaw && candidateLines.length < baselineLines.length) {
      return false;
    }

    final numberedListCount = RegExp(
      r'^\d+\.',
      multiLine: true,
    ).allMatches(rawContent).length;
    final candidateNumberedCount = RegExp(
      r'^\d+\.',
      multiLine: true,
    ).allMatches(normalizedCandidate).length;
    if (numberedListCount >= 2 && candidateNumberedCount < numberedListCount) {
      return false;
    }

    if (rawContent.contains('Title:') &&
        !normalizedCandidate.contains('Title:')) {
      return false;
    }

    return true;
  }

  List<String> _meaningfulLines(String input) {
    return input
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  String _applyFormatterFallback(
    String input,
    List<EnhancementChange> changes,
    ProcessorToggles toggles,
  ) {
    var working = input;
    if (toggles.spelling) {
      final corrected = _applySpelling(working);
      if (corrected != working) {
        working = corrected;
        changes.add(
          const EnhancementChange(
            type: ChangeType.spelling,
            label: 'Spelling cleanup',
            description:
                'Corrected common note-taking typos and normalized sentence starts.',
          ),
        );
      }
    }

    if (toggles.formatting) {
      final formatted = _applyFormatting(working);
      if (formatted != working) {
        working = formatted;
        changes.add(
          const EnhancementChange(
            type: ChangeType.formatting,
            label: 'Structured layout',
            description:
                'Converted rough lines into a readable outline with sections and bullets.',
          ),
        );
      }
    }

    if (toggles.clarity) {
      final clarified = _applyClarity(working);
      if (clarified != working) {
        working = clarified;
        changes.add(
          const EnhancementChange(
            type: ChangeType.clarity,
            label: 'Clarity pass',
            description:
                'Smoothed phrasing while keeping the note faithful to the original meaning.',
          ),
        );
      }
    }

    return working;
  }

  String _applySpelling(String input) {
    var output = input;
    const replacements = {
      ' teh ': ' the ',
      ' recieve ': ' receive ',
      ' seperate ': ' separate ',
      ' definately ': ' definitely ',
      ' dont ': " don't ",
      ' cant ': " can't ",
      'w/': 'with',
      'im ': "I'm ",
    };
    replacements.forEach((source, target) {
      output = output.replaceAll(source, target);
    });

    final lines = output.split('\n').map((line) => line.trimRight()).map((
      line,
    ) {
      if (line.isEmpty) {
        return line;
      }
      return line[0].toUpperCase() + line.substring(1);
    }).toList();
    return lines.join('\n');
  }

  String _applyFormatting(String input) {
    final lines = input
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      return input;
    }

    final buffer = StringBuffer();
    buffer.writeln('# Enhanced Note');
    buffer.writeln();

    final first = lines.first;
    if (!first.startsWith('- ') && !first.endsWith(':')) {
      buffer.writeln('## Core Thought');
      buffer.writeln(first);
      buffer.writeln();
    }

    final remaining = lines.skip(1).toList();
    if (remaining.isNotEmpty) {
      buffer.writeln('## Details');
      for (final line in remaining) {
        if (line.endsWith(':')) {
          buffer.writeln();
          buffer.writeln('### ${line.substring(0, line.length - 1)}');
        } else if (line.startsWith('- ') || line.startsWith('* ')) {
          buffer.writeln('- ${line.substring(2).trim()}');
        } else {
          buffer.writeln('- $line');
        }
      }
    }

    return buffer.toString().trim();
  }

  String _applyClarity(String input) {
    return input
        .replaceAll('need to', 'should')
        .replaceAll('a lot of', 'many')
        .replaceAll('really important', 'important')
        .replaceAll('kind of', 'somewhat');
  }

  List<VerificationFlag> _detectVerificationFlags(String input) {
    final flags = <VerificationFlag>[];
    final lower = input.toLowerCase();

    if (lower.contains('2027') || lower.contains('next year')) {
      flags.add(
        const VerificationFlag(
          status: VerificationStatus.warning,
          claimText: 'Timeline or future-date claim',
          note:
              'Future-looking dates often drift. Confirm this before turning it into a decision log.',
          confidence: 0.46,
        ),
      );
    }

    final numbers = RegExp(r'\b\d{3,}\b').allMatches(input).length;
    if (numbers > 0) {
      flags.add(
        const VerificationFlag(
          status: VerificationStatus.needsReview,
          claimText: 'Numeric claim detected',
          note:
              'Large numbers and metrics should link back to a source or meeting artifact.',
          confidence: 0.61,
        ),
      );
    }

    if (lower.contains('according to') || lower.contains('research says')) {
      flags.add(
        const VerificationFlag(
          status: VerificationStatus.warning,
          claimText: 'External source claim',
          note: 'This sounds sourced but the citation is missing in the note.',
          confidence: 0.74,
        ),
      );
    }

    return flags;
  }

  String _buildSummary(String input) {
    final sentences = input
        .split(RegExp(r'[\n\.]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .take(2)
        .toList();

    if (sentences.isEmpty) {
      return 'No summary yet.';
    }

    return sentences.join(' ').trim();
  }
}

class UnavailableLocalModelAdapter extends LocalModelAdapter {
  const UnavailableLocalModelAdapter();

  @override
  Future<FormatterProcessorResult> runFormatter({
    required EnhancementRequest request,
  }) async {
    return const FormatterProcessorResult(
      enhancedText: '',
      changes: [],
      status: ProcessorStatus(
        kind: ProcessorKind.formatter,
        state: ProcessorState.unavailable,
        label: 'Formatter',
        detail: 'No local model runtime detected.',
      ),
    );
  }

  @override
  Future<VerifierProcessorResult> runVerifier({
    required EnhancementRequest request,
    required String enhancedText,
  }) async {
    return const VerifierProcessorResult(
      flags: [],
      changes: [],
      status: ProcessorStatus(
        kind: ProcessorKind.verifier,
        state: ProcessorState.unavailable,
        label: 'Verifier',
        detail: 'No local model runtime detected.',
      ),
    );
  }
}
