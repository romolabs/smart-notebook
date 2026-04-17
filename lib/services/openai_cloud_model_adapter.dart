import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/notebook_models.dart';
import 'ai_command_service.dart';
import 'mock_enhancement_engine.dart';

class OpenAiCloudModelAdapter extends CloudCommandAdapter {
  const OpenAiCloudModelAdapter({
    required this.baseUrl,
    required this.apiKey,
    required this.preferredModel,
    required this.fallbackMiniModel,
    this.requestTimeout = const Duration(seconds: 20),
  });

  final String baseUrl;
  final String apiKey;
  final String preferredModel;
  final String fallbackMiniModel;
  final Duration requestTimeout;

  @override
  Future<AiCommandResult> runAiCommand({
    required EnhancementRequest request,
    required AiCommandRequest command,
  }) async {
    if (apiKey.trim().isEmpty) {
      return AiCommandResult(
        request: command,
        status: AiCommandStatus.unavailable,
        title: command.resultTitle,
        content: '',
        detail: 'OpenAI API key is missing.',
        providerLabel: 'Cloud AI unavailable',
      );
    }

    final prompt = _buildAiCommandPrompt(request: request, command: command);
    final modelsToTry = <String>[
      preferredModel.trim(),
      fallbackMiniModel.trim(),
    ].where((model) => model.isNotEmpty).toSet().toList(growable: false);

    Object? lastError;
    for (final model in modelsToTry) {
      try {
        final payload = await _generateJson(model: model, prompt: prompt);
        final title = (_readString(payload['title']) ?? command.resultTitle)
            .trim();
        final content =
            (_readString(payload['response'] ?? payload['content']) ?? '')
                .trim();
        if (content.isEmpty) {
          throw const FormatException(
            'The cloud model returned an empty AI response.',
          );
        }

        return AiCommandResult(
          request: command,
          status: AiCommandStatus.completed,
          title: title.isEmpty ? command.resultTitle : title,
          content: content,
          detail: 'Generated with OpenAI $model.',
          providerLabel: 'OpenAI $model',
        );
      } catch (error) {
        lastError = error;
      }
    }

    final providerModel = modelsToTry.isEmpty ? 'cloud model' : modelsToTry[0];
    return AiCommandResult(
      request: command,
      status: AiCommandStatus.failed,
      title: command.resultTitle,
      content: '',
      detail: 'OpenAI AI command failed: $lastError',
      providerLabel: 'OpenAI $providerModel',
    );
  }

  Future<Map<String, dynamic>> _generateJson({
    required String model,
    required String prompt,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final uri = Uri.parse('${_normalizedBaseUrl()}/responses');
      final request = await client.postUrl(uri).timeout(requestTimeout);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write(
        jsonEncode({
          'model': model,
          'store': false,
          'temperature': 0.1,
          'input': [
            {
              'role': 'system',
              'content': [
                {
                  'type': 'input_text',
                  'text':
                      'You are the cloud AI command responder for Smart Notebook. Return valid JSON only.',
                },
              ],
            },
            {
              'role': 'user',
              'content': [
                {'type': 'input_text', 'text': prompt},
              ],
            },
          ],
          'text': {
            'format': {
              'type': 'json_schema',
              'name': 'smart_notebook_ai_command',
              'strict': true,
              'schema': {
                'type': 'object',
                'additionalProperties': false,
                'properties': {
                  'title': {'type': 'string'},
                  'response': {'type': 'string'},
                },
                'required': ['title', 'response'],
              },
            },
          },
        }),
      );

      final response = await request.close().timeout(requestTimeout);
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = _readErrorMessage(body);
        throw HttpException(
          message == null
              ? 'Unexpected OpenAI status ${response.statusCode}'
              : 'Unexpected OpenAI status ${response.statusCode}: $message',
          uri: uri,
        );
      }

      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final content = _extractResponseText(decoded);
      return _decodeModelJson(content);
    } finally {
      client.close(force: true);
    }
  }

  String _extractResponseText(Map<String, dynamic> payload) {
    final output = payload['output'];
    if (output is! List || output.isEmpty) {
      throw const FormatException('OpenAI response did not include output.');
    }

    final buffer = StringBuffer();
    for (final item in output) {
      if (item is! Map) {
        continue;
      }
      final content = item['content'];
      if (content is! List) {
        continue;
      }
      for (final chunk in content) {
        if (chunk is! Map) {
          continue;
        }
        final type = chunk['type'];
        if (type == 'output_text') {
          final text = chunk['text'];
          if (text is String) {
            buffer.write(text);
          }
        }
      }
    }

    final combined = buffer.toString().trim();
    if (combined.isEmpty) {
      throw const FormatException(
        'OpenAI response did not include assistant text content.',
      );
    }
    return combined;
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

  String? _readErrorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          return _readString(error['message'])?.trim();
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String _buildAiCommandPrompt({
    required EnhancementRequest request,
    required AiCommandRequest command,
  }) {
    final argument = command.argument == null || command.argument!.isEmpty
        ? 'none'
        : command.argument!;
    final taskInstruction = switch (command.kind) {
      AiCommandKind.explain =>
        'Explain the referenced note content in clearer, more helpful prose without changing the original note.',
      AiCommandKind.explainFormula =>
        'Explain the referenced formula or math block in plain language. Do not rewrite or modify the formula itself.',
      AiCommandKind.define =>
        'Define the requested term using the local note context when helpful. Stay concise and grounded.',
      AiCommandKind.summarize =>
        'Summarize the referenced context in a compact and faithful way.',
      AiCommandKind.factCheck =>
        'Review the referenced context and point out what the user may want to verify. Stay calm and avoid unsupported certainty.',
    };

    return '''
Return one JSON object only.

Role: explicit AI command responder for Smart Notebook.
Task: $taskInstruction

Rules:
- This is an additive response, not a note rewrite.
- Use only the command context and command argument below.
- Keep formulas, symbols, and code exactly as written when quoting them.
- Be concise, concrete, and helpful.
- For fact-check requests, do not claim something is false unless the provided context itself contradicts it.
- If context is empty, say so plainly.

JSON schema:
{"title":"string","response":"string"}

Mode: ${request.modelMode.name}
Command: ${command.displayLabel}
Argument: $argument

Context between <context> tags.
<context>
${command.context}
</context>
''';
  }

  String? _readString(Object? value) {
    if (value is String) {
      return value;
    }
    return null;
  }

  String _normalizedBaseUrl() {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) {
      return 'https://api.openai.com/v1';
    }
    final withoutTrailingSlash = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    if (withoutTrailingSlash.endsWith('/v1')) {
      return withoutTrailingSlash;
    }
    return '$withoutTrailingSlash/v1';
  }
}
