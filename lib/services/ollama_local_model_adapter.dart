import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/notebook_models.dart';
import 'mock_enhancement_engine.dart';

class OllamaLocalModelAdapter extends LocalModelAdapter {
  const OllamaLocalModelAdapter({
    this.baseUrl = 'http://127.0.0.1:11434',
    this.model = 'gemma4:e4b',
    this.requestTimeout = const Duration(seconds: 8),
    this.probeTtl = const Duration(seconds: 10),
  });

  final String baseUrl;
  final String model;
  final Duration requestTimeout;
  final Duration probeTtl;

  static DateTime? _lastProbeAt;
  static String? _lastProbeKey;
  static bool _lastReachable = false;
  static Set<String> _lastModels = const {};

  @override
  Future<FormatterProcessorResult> runFormatter({
    required EnhancementRequest request,
    required ChampionDraft champion,
    required RoutePlan routePlan,
  }) async {
    final probe = await _probeRuntime();
    if (!probe.modelAvailable) {
      return FormatterProcessorResult(
        proposal: const ModelProposal(),
        status: ProcessorStatus(
          kind: ProcessorKind.formatter,
          state: ProcessorState.unavailable,
          label: 'Formatter',
          detail: probe.detail,
        ),
      );
    }

    try {
      final payload = await _generateJson(
        _buildFormatterPrompt(
          request: request,
          champion: champion,
          routePlan: routePlan,
        ),
      );
      final proposal = _parseModelProposal(payload);
      final legacyWholeNoteResponse =
          _readString(payload['enhancedText'])?.trim().isNotEmpty == true;
      final proposalCount =
          proposal.lineEdits.length + proposal.artifacts.length;
      return FormatterProcessorResult(
        proposal: proposal,
        status: ProcessorStatus(
          kind: ProcessorKind.formatter,
          state: ProcessorState.completed,
          label: 'Formatter',
          detail: proposalCount > 0
              ? 'Processed with Ollama $model and parsed $proposalCount bounded proposal item(s).'
              : legacyWholeNoteResponse
              ? 'Processed with Ollama $model, but ignored whole-note output and kept an empty bounded proposal.'
              : 'Processed with Ollama $model and returned no bounded proposal items.',
        ),
      );
    } catch (error) {
      return FormatterProcessorResult(
        proposal: const ModelProposal(),
        status: ProcessorStatus(
          kind: ProcessorKind.formatter,
          state: ProcessorState.failed,
          label: 'Formatter',
          detail: 'Ollama formatter failed: $error',
        ),
      );
    }
  }

  @override
  Future<VerifierProcessorResult> runVerifier({
    required EnhancementRequest request,
    required String enhancedText,
  }) async {
    final probe = await _probeRuntime();
    if (!probe.modelAvailable) {
      return VerifierProcessorResult(
        flags: [],
        changes: [],
        status: ProcessorStatus(
          kind: ProcessorKind.verifier,
          state: ProcessorState.unavailable,
          label: 'Verifier',
          detail: probe.detail,
        ),
      );
    }

    try {
      final payload = await _generateJson(
        _buildVerifierPrompt(request: request, enhancedText: enhancedText),
      );
      return VerifierProcessorResult(
        flags: _parseVerificationFlags(payload['verificationFlags']),
        changes: _parseChangeItems(payload['changeItems']),
        status: ProcessorStatus(
          kind: ProcessorKind.verifier,
          state: ProcessorState.completed,
          label: 'Verifier',
          detail: 'Processed with Ollama $model.',
        ),
      );
    } catch (error) {
      return VerifierProcessorResult(
        flags: const [],
        changes: const [],
        status: ProcessorStatus(
          kind: ProcessorKind.verifier,
          state: ProcessorState.failed,
          label: 'Verifier',
          detail: 'Ollama verifier failed: $error',
        ),
      );
    }
  }

  Future<_ProbeResult> _probeRuntime() async {
    final now = DateTime.now();
    final probeKey = '$baseUrl|$model';
    if (_lastProbeKey == probeKey &&
        _lastProbeAt != null &&
        now.difference(_lastProbeAt!) < probeTtl) {
      return _buildProbeResult();
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      final uri = Uri.parse('$baseUrl/api/tags');
      final request = await client.getUrl(uri).timeout(requestTimeout);
      final response = await request.close().timeout(requestTimeout);
      if (response.statusCode != 200) {
        _lastProbeKey = probeKey;
        _lastProbeAt = now;
        _lastReachable = false;
        _lastModels = const {};
        return _buildProbeResult();
      }

      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final models = ((decoded['models'] as List<dynamic>?) ?? const [])
          .map((item) => item as Map<String, dynamic>)
          .map((item) => item['name'] as String? ?? '')
          .where((item) => item.isNotEmpty)
          .toSet();
      _lastProbeKey = probeKey;
      _lastProbeAt = now;
      _lastReachable = true;
      _lastModels = models;
      return _buildProbeResult();
    } catch (_) {
      _lastProbeKey = probeKey;
      _lastProbeAt = now;
      _lastReachable = false;
      _lastModels = const {};
      return _buildProbeResult();
    } finally {
      client.close(force: true);
    }
  }

  _ProbeResult _buildProbeResult() {
    if (!_lastReachable) {
      return const _ProbeResult(
        reachable: false,
        modelAvailable: false,
        detail: 'No local model runtime detected.',
      );
    }
    if (!_lastModels.contains(model)) {
      return _ProbeResult(
        reachable: true,
        modelAvailable: false,
        detail: 'Ollama is running, but model "$model" is not installed.',
      );
    }
    return const _ProbeResult(
      reachable: true,
      modelAvailable: true,
      detail: 'Local model runtime detected.',
    );
  }

  Future<Map<String, dynamic>> _generateJson(String prompt) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      final uri = Uri.parse('$baseUrl/api/generate');
      final request = await client.postUrl(uri).timeout(requestTimeout);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'model': model,
          'prompt': prompt,
          'stream': false,
          'format': 'json',
          'options': {'temperature': 0.1, 'top_p': 0.9},
        }),
      );

      final response = await request.close().timeout(requestTimeout);
      if (response.statusCode != 200) {
        throw HttpException(
          'Unexpected Ollama status ${response.statusCode}',
          uri: uri,
        );
      }

      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final modelResponse = decoded['response'] as String? ?? '{}';
      return _decodeModelJson(modelResponse);
    } finally {
      client.close(force: true);
    }
  }

  Map<String, dynamic> _decodeModelJson(String modelResponse) {
    final trimmed = modelResponse.trim();
    try {
      return jsonDecode(trimmed) as Map<String, dynamic>;
    } on FormatException {
      final start = trimmed.indexOf('{');
      final end = trimmed.lastIndexOf('}');
      if (start < 0 || end <= start) {
        rethrow;
      }
      final candidate = trimmed.substring(start, end + 1);
      return jsonDecode(candidate) as Map<String, dynamic>;
    }
  }

  String _buildFormatterPrompt({
    required EnhancementRequest request,
    required ChampionDraft champion,
    required RoutePlan routePlan,
  }) {
    final enabled = <String>[
      if (request.toggles.spelling) 'spelling',
      if (request.toggles.formatting) 'formatting',
      if (request.toggles.clarity) 'clarity',
    ].join(', ');
    final allowedCapabilities = routePlan.allowedCapabilities
        .map((capability) => capability.name)
        .join(', ');
    final editableLineIndexes = routePlan.editableLineIndexes.join(', ');

    return '''
Return one JSON object only.

Role: bounded formatter proposal generator for Smart Notebook.
Goal: propose only the safest single-line edits for $enabled against the champion draft.
Route summary: ${routePlan.summary}
Allowed capabilities: ${allowedCapabilities.isEmpty ? 'none' : allowedCapabilities}
Editable line indexes: ${editableLineIndexes.isEmpty ? 'none' : editableLineIndexes}

Rules:
- Do not return the final enhanced note.
- Return only bounded proposals against existing champion draft line indexes.
- Preserve meaning, line order, block order, and structure.
- Make the smallest safe edits.
- Do not invent facts, names, dates, numbers, tasks, or sources.
- Do not propose edits for blank, code, heading, or tableRow lines.
- Each replacement must be exactly one non-empty line with no newline characters.
- Keep numbered lists as numbered lists and preserve checkbox state.
- Sidecar artifacts are allowed only when clearly grounded in the cited evidence lines.
- Suggested titles must reuse source language.
- Summaries must use only source information.
- Action items must stay evidence-backed and must not guess missing owners or dates.
- If no safe edit is needed, return empty arrays.
- Keep at most 3 lineEdits.
- Keep at most 3 artifacts.
- Keep labels and descriptions short.
- Never propose a line edit for any line index not listed as editable.
- If allowed capabilities do not include lineEdits, return an empty lineEdits array.
- If allowed capabilities do not include an artifact category, do not return that artifact kind.

JSON schema:
{"lineEdits":[{"lineIndex":0,"replacement":"string","type":"spelling|formatting|clarity","label":"string","description":"string"}],"artifacts":[{"kind":"title|summary|actionItems","value":"string","evidenceLineIndexes":[0],"label":"string","description":"string"}]}

Champion draft lines between <champion> tags.
Use the exact lineIndex values shown below.
<champion>
${_buildIndexedChampionLines(champion)}
</champion>
''';
  }

  String _buildIndexedChampionLines(ChampionDraft champion) {
    return champion.structure.lines
        .map((line) {
          final rendered =
              champion.renderedLinesBySourceIndex[line.index] ??
              line.sourceLine.trimRight();
          final display = rendered.isEmpty ? '<BLANK>' : rendered;
          return '${line.index}|${line.kind.name}|$display';
        })
        .join('\n');
  }

  String _buildVerifierPrompt({
    required EnhancementRequest request,
    required String enhancedText,
  }) {
    return '''
Return one JSON object only.

Role: verifier for Smart Notebook.
Goal: flag only claims that may need manual checking.

Rules:
- Be conservative.
- Do not rewrite the note.
- Do not invent facts or sources.
- Prefer zero flags over weak guesses.
- Keep flags to 3 or fewer.
- note must be short and explain why to review.
- confidence must be between 0.0 and 1.0.

JSON schema:
{"verificationFlags":[{"status":"warning|needsReview","claimText":"string","note":"string","confidence":0.0}],"changeItems":[]}

Raw note between <raw> tags.
<raw>
${request.rawContent}
</raw>

Enhanced note between <enhanced> tags.
<enhanced>
$enhancedText
</enhanced>
''';
  }

  ModelProposal _parseModelProposal(Object? value) {
    final payload = _extractProposalPayload(value);
    if (payload == null) {
      return const ModelProposal();
    }

    return ModelProposal(
      lineEdits: _parseLineEditProposals(
        payload['lineEdits'] ??
            payload['lineEditProposals'] ??
            payload['line_edits'] ??
            payload['edits'],
      ),
      artifacts: _parseArtifactProposals(
        payload['artifacts'] ??
            payload['artifactProposals'] ??
            payload['artifact_proposals'],
      ),
    );
  }

  Map<String, dynamic>? _extractProposalPayload(Object? value) {
    final map = _asObjectMap(value);
    if (map == null) {
      return null;
    }

    final nested =
        _asObjectMap(map['proposal']) ?? _asObjectMap(map['modelProposal']);
    if (nested != null) {
      return nested;
    }

    return map;
  }

  List<LineEditProposal> _parseLineEditProposals(Object? value) {
    final rawItems = _asList(value);
    return rawItems
        .map(_parseLineEditProposal)
        .whereType<LineEditProposal>()
        .toList(growable: false);
  }

  LineEditProposal? _parseLineEditProposal(Object? value) {
    final map = _asObjectMap(value);
    if (map == null) {
      return null;
    }

    final lineIndex = _parseLineIndex(
      map['lineIndex'] ?? map['line'] ?? map['index'] ?? map['line_number'],
    );
    final replacement =
        (_readString(
                  map['replacement'] ??
                      map['text'] ??
                      map['value'] ??
                      map['replacementLine'],
                ) ??
                '')
            .trim();

    if (lineIndex == null ||
        replacement.isEmpty ||
        replacement.contains('\n') ||
        replacement.contains('\r')) {
      return null;
    }

    return LineEditProposal(
      lineIndex: lineIndex,
      replacement: replacement,
      type: _parseChangeType(_readString(map['type'] ?? map['changeType'])),
      label: _readString(map['label']) ?? 'Model edit for line $lineIndex',
      description:
          _readString(map['description']) ?? 'Model-suggested bounded edit.',
    );
  }

  List<ArtifactProposal> _parseArtifactProposals(Object? value) {
    final rawItems = _asList(value);
    return rawItems
        .map(_parseArtifactProposal)
        .whereType<ArtifactProposal>()
        .toList(growable: false);
  }

  ArtifactProposal? _parseArtifactProposal(Object? value) {
    final map = _asObjectMap(value);
    if (map == null) {
      return null;
    }

    final kind = _parseArtifactKind(
      _readString(map['kind'] ?? map['type'] ?? map['artifactKind']),
    );
    final proposalValue =
        (_readString(map['value'] ?? map['text'] ?? map['content']) ?? '')
            .trim();
    final evidenceLineIndexes = _parseIntList(
      map['evidenceLineIndexes'] ??
          map['evidenceLines'] ??
          map['evidence'] ??
          map['lineIndexes'],
    );

    if (kind == null || proposalValue.isEmpty) {
      return null;
    }

    return ArtifactProposal(
      kind: kind,
      value: proposalValue,
      evidenceLineIndexes: evidenceLineIndexes,
      label: _readString(map['label']) ?? 'Model artifact',
      description:
          _readString(map['description']) ??
          'Model-suggested sidecar artifact.',
    );
  }

  List<EnhancementChange> _parseChangeItems(Object? value) {
    final rawItems = _asList(value);
    return rawItems
        .map((item) {
          final map = _asObjectMap(item);
          if (map == null) {
            return null;
          }
          return EnhancementChange(
            type: _parseChangeType(
              _readString(map['type'] ?? map['changeType']),
            ),
            label: _readString(map['label']) ?? 'Model change',
            description:
                _readString(map['description']) ?? 'Model-suggested edit.',
          );
        })
        .whereType<EnhancementChange>()
        .toList(growable: false);
  }

  List<VerificationFlag> _parseVerificationFlags(Object? value) {
    final rawItems = _asList(value);
    return rawItems
        .map((item) {
          final map = _asObjectMap(item);
          if (map == null) {
            return null;
          }
          return VerificationFlag(
            status: _parseVerificationStatus(_readString(map['status'])),
            claimText:
                _readString(map['claimText'] ?? map['claim']) ??
                'Potential factual claim',
            note: _readString(map['note']) ?? 'Review recommended.',
            confidence: _parseDouble(map['confidence']) ?? 0.5,
          );
        })
        .whereType<VerificationFlag>()
        .toList(growable: false);
  }

  ChangeType _parseChangeType(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'spelling' => ChangeType.spelling,
      'formatting' => ChangeType.formatting,
      'clarity' => ChangeType.clarity,
      'verification' => ChangeType.verification,
      _ => ChangeType.clarity,
    };
  }

  ArtifactKind? _parseArtifactKind(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'title' => ArtifactKind.title,
      'summary' => ArtifactKind.summary,
      'actionitems' ||
      'action items' ||
      'action_items' ||
      'action-items' => ArtifactKind.actionItems,
      _ => null,
    };
  }

  VerificationStatus _parseVerificationStatus(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'needsreview' ||
      'needs_review' ||
      'needs-review' => VerificationStatus.needsReview,
      _ => VerificationStatus.warning,
    };
  }

  Map<String, dynamic>? _asObjectMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (key, entryValue) => MapEntry(key.toString(), entryValue),
      );
    }
    return null;
  }

  List<dynamic> _asList(Object? value) {
    if (value is List<dynamic>) {
      return value;
    }
    if (value == null) {
      return const [];
    }
    return [value];
  }

  String? _readString(Object? value) {
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (value is num || value is bool) {
      return value.toString();
    }
    return null;
  }

  int? _parseLineIndex(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    final raw = _readString(value);
    if (raw == null) {
      return null;
    }
    final match = RegExp(r'-?\d+').firstMatch(raw);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  List<int> _parseIntList(Object? value) {
    if (value is List<dynamic>) {
      return value
          .map(_parseLineIndex)
          .whereType<int>()
          .toList(growable: false);
    }

    final raw = _readString(value);
    if (raw == null) {
      return const [];
    }

    return RegExp(r'-?\d+')
        .allMatches(raw)
        .map((match) => int.parse(match.group(0)!))
        .toList(growable: false);
  }

  double? _parseDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    final raw = _readString(value);
    return raw == null ? null : double.tryParse(raw);
  }
}

class _ProbeResult {
  const _ProbeResult({
    required this.reachable,
    required this.modelAvailable,
    required this.detail,
  });

  final bool reachable;
  final bool modelAvailable;
  final String detail;
}
