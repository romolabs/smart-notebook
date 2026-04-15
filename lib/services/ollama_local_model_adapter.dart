import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/notebook_models.dart';
import 'mock_enhancement_engine.dart';

class OllamaLocalModelAdapter extends LocalModelAdapter {
  const OllamaLocalModelAdapter({
    this.baseUrl = 'http://127.0.0.1:11434',
    this.model = 'gemma3:1b',
    this.requestTimeout = const Duration(seconds: 8),
    this.probeTtl = const Duration(seconds: 10),
  });

  final String baseUrl;
  final String model;
  final Duration requestTimeout;
  final Duration probeTtl;

  static DateTime? _lastProbeAt;
  static bool _lastReachable = false;
  static Set<String> _lastModels = const {};

  @override
  Future<FormatterProcessorResult> runFormatter({
    required EnhancementRequest request,
  }) async {
    final available = await _ensureModelAvailable();
    if (!available) {
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

    try {
      final payload = await _generateJson(_buildFormatterPrompt(request));
      final enhancedText =
          (payload['enhancedText'] as String?)?.trim() ??
          request.rawContent.trim();
      final changeItems = _parseChangeItems(payload['changeItems']);
      return FormatterProcessorResult(
        enhancedText: enhancedText.isEmpty
            ? request.rawContent.trim()
            : enhancedText,
        changes: changeItems,
        status: ProcessorStatus(
          kind: ProcessorKind.formatter,
          state: ProcessorState.completed,
          label: 'Formatter',
          detail: 'Processed with Ollama $model.',
        ),
      );
    } catch (error) {
      return FormatterProcessorResult(
        enhancedText: request.rawContent.trim(),
        changes: const [],
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
    final available = await _ensureModelAvailable();
    if (!available) {
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

  Future<bool> _ensureModelAvailable() async {
    final now = DateTime.now();
    if (_lastProbeAt != null && now.difference(_lastProbeAt!) < probeTtl) {
      return _lastReachable && _lastModels.contains(model);
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      final uri = Uri.parse('$baseUrl/api/tags');
      final request = await client.getUrl(uri).timeout(requestTimeout);
      final response = await request.close().timeout(requestTimeout);
      if (response.statusCode != 200) {
        _lastProbeAt = now;
        _lastReachable = false;
        _lastModels = const {};
        return false;
      }

      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final models = ((decoded['models'] as List<dynamic>?) ?? const [])
          .map((item) => item as Map<String, dynamic>)
          .map((item) => item['name'] as String? ?? '')
          .where((item) => item.isNotEmpty)
          .toSet();
      _lastProbeAt = now;
      _lastReachable = true;
      _lastModels = models;
      return models.contains(model);
    } catch (_) {
      _lastProbeAt = now;
      _lastReachable = false;
      _lastModels = const {};
      return false;
    } finally {
      client.close(force: true);
    }
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

  String _buildFormatterPrompt(EnhancementRequest request) {
    final enabled = <String>[
      if (request.toggles.spelling) 'spelling',
      if (request.toggles.formatting) 'formatting',
      if (request.toggles.clarity) 'clarity',
    ].join(', ');

    return '''
Return one JSON object only.

Role: formatter for Smart Notebook.
Goal: improve only $enabled.

Rules:
- Preserve meaning and original order.
- Make the smallest safe edits.
- Do not invent facts, names, dates, numbers, tasks, or sources.
- If the note is already clear, return it unchanged.
- Keep at most 3 changeItems.
- Each description must be short.

JSON schema:
{"enhancedText":"string","changeItems":[{"type":"spelling|formatting|clarity","label":"string","description":"string"}]}

Raw note between <note> tags.
<note>
${request.rawContent}
</note>
''';
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

  List<EnhancementChange> _parseChangeItems(Object? value) {
    final rawItems = value as List<dynamic>? ?? const [];
    return rawItems
        .map((item) {
          final map = item as Map<String, dynamic>;
          return EnhancementChange(
            type: _parseChangeType(map['type'] as String?),
            label: map['label'] as String? ?? 'Model change',
            description:
                map['description'] as String? ?? 'Model-suggested edit.',
          );
        })
        .toList(growable: false);
  }

  List<VerificationFlag> _parseVerificationFlags(Object? value) {
    final rawItems = value as List<dynamic>? ?? const [];
    return rawItems
        .map((item) {
          final map = item as Map<String, dynamic>;
          return VerificationFlag(
            status: _parseVerificationStatus(map['status'] as String?),
            claimText: map['claimText'] as String? ?? 'Potential factual claim',
            note: map['note'] as String? ?? 'Review recommended.',
            confidence: (map['confidence'] as num?)?.toDouble() ?? 0.5,
          );
        })
        .toList(growable: false);
  }

  ChangeType _parseChangeType(String? value) {
    return switch (value) {
      'spelling' => ChangeType.spelling,
      'formatting' => ChangeType.formatting,
      'clarity' => ChangeType.clarity,
      'verification' => ChangeType.verification,
      _ => ChangeType.clarity,
    };
  }

  VerificationStatus _parseVerificationStatus(String? value) {
    return switch (value) {
      'needsReview' => VerificationStatus.needsReview,
      _ => VerificationStatus.warning,
    };
  }
}
