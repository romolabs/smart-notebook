enum AiCommandKind { explain, explainFormula, define, summarize, factCheck }

enum AiCommandStatus { running, completed, unavailable, failed }

class AiCommandLine {
  const AiCommandLine({
    required this.lineIndex,
    required this.rawLine,
    required this.commandText,
  });

  final int lineIndex;
  final String rawLine;
  final String commandText;
}

class AiCommandRequest {
  const AiCommandRequest({
    required this.kind,
    required this.lineIndex,
    required this.rawCommand,
    required this.context,
    this.argument,
  });

  final AiCommandKind kind;
  final int lineIndex;
  final String rawCommand;
  final String context;
  final String? argument;

  String get id {
    final argumentPart = argument ?? '';
    final contextHash = context.hashCode;
    return '$lineIndex|${kind.name}|$argumentPart|$contextHash';
  }

  String get displayLabel {
    return switch (kind) {
      AiCommandKind.explain =>
        argument == null ? '//explain' : '//explain $argument',
      AiCommandKind.explainFormula => '//explain formula',
      AiCommandKind.define => '//define ${argument ?? ''}'.trimRight(),
      AiCommandKind.summarize =>
        argument == null ? '//summarize' : '//summarize $argument',
      AiCommandKind.factCheck =>
        argument == null ? '//fact check' : '//fact check $argument',
    };
  }

  String get resultTitle {
    return switch (kind) {
      AiCommandKind.explain => 'AI Explanation',
      AiCommandKind.explainFormula => 'Formula Explanation',
      AiCommandKind.define => 'Definition',
      AiCommandKind.summarize => 'AI Summary',
      AiCommandKind.factCheck => 'Fact Check Review',
    };
  }
}

class AiCommandResult {
  const AiCommandResult({
    required this.request,
    required this.status,
    required this.title,
    required this.content,
    required this.detail,
    required this.providerLabel,
  });

  final AiCommandRequest request;
  final AiCommandStatus status;
  final String title;
  final String content;
  final String detail;
  final String providerLabel;

  bool get isTerminal =>
      status == AiCommandStatus.completed ||
      status == AiCommandStatus.unavailable ||
      status == AiCommandStatus.failed;
}

class AiCommandService {
  const AiCommandService();

  static const String _mathDirectiveStart = '/math';
  static const String _directiveEnd = '/end';

  List<AiCommandLine> extractCommandLines(String rawText) {
    final lines = _normalize(rawText).split('\n');
    final commands = <AiCommandLine>[];

    for (var index = 0; index < lines.length; index++) {
      final commandText = _commandText(lines[index]);
      if (commandText == null) {
        continue;
      }
      commands.add(
        AiCommandLine(
          lineIndex: index,
          rawLine: lines[index],
          commandText: commandText,
        ),
      );
    }

    return commands;
  }

  String stripCommandLines(String rawText) {
    final normalized = _normalize(rawText);
    final lines = normalized.split('\n');
    final kept = <String>[];

    for (final line in lines) {
      if (_commandText(line) == null) {
        kept.add(line);
      }
    }

    final stripped = kept.join('\n');
    if (normalized.endsWith('\n') && !stripped.endsWith('\n')) {
      return '$stripped\n';
    }
    return stripped;
  }

  List<AiCommandRequest> parseCommands(String rawText) {
    final normalized = _normalize(rawText);
    final commandLines = extractCommandLines(normalized);

    return commandLines
        .map((line) {
          final match = _matchCommand(line.commandText);
          if (match == null) {
            return null;
          }

          return AiCommandRequest(
            kind: match.kind,
            lineIndex: line.lineIndex,
            rawCommand: line.commandText,
            argument: match.argument,
            context: resolveContext(
              rawText: normalized,
              commandLineIndex: line.lineIndex,
              kind: match.kind,
            ),
          );
        })
        .whereType<AiCommandRequest>()
        .toList(growable: false);
  }

  String resolveContext({
    required String rawText,
    required int commandLineIndex,
    required AiCommandKind kind,
  }) {
    final lines = _normalize(rawText).split('\n');
    if (kind == AiCommandKind.explainFormula) {
      final mathContext = _nearestPrecedingMathBlock(
        lines: lines,
        fromLineIndex: commandLineIndex - 1,
      );
      if (mathContext.isNotEmpty) {
        return mathContext;
      }
    }

    return _nearestPrecedingProseBlock(
      lines: lines,
      fromLineIndex: commandLineIndex - 1,
    );
  }

  String _normalize(String rawText) {
    return rawText.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  String? _commandText(String line) {
    final trimmedLeft = line.trimLeft();
    if (!trimmedLeft.startsWith('//')) {
      return null;
    }
    return trimmedLeft.substring(2).trim();
  }

  _AiCommandMatch? _matchCommand(String commandText) {
    final normalized = commandText.trim();
    final lower = normalized.toLowerCase();

    if (lower == 'explain formula') {
      return const _AiCommandMatch(kind: AiCommandKind.explainFormula);
    }

    if (lower == 'explain' || lower.startsWith('explain ')) {
      return _AiCommandMatch(
        kind: AiCommandKind.explain,
        argument: _suffix(normalized, 'explain'),
      );
    }

    if (lower.startsWith('define ')) {
      final argument = normalized.substring('define '.length).trim();
      if (argument.isEmpty) {
        return null;
      }
      return _AiCommandMatch(kind: AiCommandKind.define, argument: argument);
    }

    if (lower == 'summarize' || lower.startsWith('summarize ')) {
      return _AiCommandMatch(
        kind: AiCommandKind.summarize,
        argument: _suffix(normalized, 'summarize'),
      );
    }

    if (lower == 'fact check' ||
        lower.startsWith('fact check ') ||
        lower == 'fact-check' ||
        lower.startsWith('fact-check ')) {
      final prefix = lower.startsWith('fact-check')
          ? 'fact-check'
          : 'fact check';
      return _AiCommandMatch(
        kind: AiCommandKind.factCheck,
        argument: _suffix(normalized, prefix),
      );
    }

    return null;
  }

  String? _suffix(String value, String prefix) {
    if (value.length <= prefix.length) {
      return null;
    }
    final suffix = value.substring(prefix.length).trim();
    return suffix.isEmpty ? null : suffix;
  }

  String _nearestPrecedingMathBlock({
    required List<String> lines,
    required int fromLineIndex,
  }) {
    if (fromLineIndex < 0) {
      return '';
    }

    for (var index = fromLineIndex; index >= 0; index--) {
      final trimmed = lines[index].trim();
      if (trimmed == _directiveEnd) {
        final start = _findMathDirectiveStart(lines, index);
        if (start != null) {
          return lines.sublist(start, index + 1).join('\n').trim();
        }
      }
    }

    return '';
  }

  int? _findMathDirectiveStart(List<String> lines, int endIndex) {
    for (var index = endIndex - 1; index >= 0; index--) {
      final trimmed = lines[index].trim();
      if (trimmed == _mathDirectiveStart) {
        return index;
      }
      if (trimmed == _directiveEnd) {
        return null;
      }
    }
    return null;
  }

  String _nearestPrecedingProseBlock({
    required List<String> lines,
    required int fromLineIndex,
  }) {
    final blocks = _contentBlocks(lines);
    for (var index = blocks.length - 1; index >= 0; index--) {
      final block = blocks[index];
      if (block.endLineIndex <= fromLineIndex) {
        return block.text;
      }
    }
    return '';
  }

  List<_TextBlock> _contentBlocks(List<String> lines) {
    final blocks = <_TextBlock>[];
    final buffer = <String>[];
    int? startLineIndex;
    var index = 0;

    void flush(int endLineIndex) {
      if (buffer.isEmpty || startLineIndex == null) {
        buffer.clear();
        startLineIndex = null;
        return;
      }

      final text = buffer.join('\n').trim();
      if (text.isNotEmpty) {
        blocks.add(
          _TextBlock(
            startLineIndex: startLineIndex!,
            endLineIndex: endLineIndex,
            text: text,
          ),
        );
      }
      buffer.clear();
      startLineIndex = null;
    }

    while (index < lines.length) {
      final line = lines[index];
      final trimmed = line.trim();

      if (_commandText(line) != null) {
        flush(index - 1);
        index++;
        continue;
      }

      if (trimmed.isEmpty) {
        flush(index - 1);
        index++;
        continue;
      }

      if (trimmed == _mathDirectiveStart) {
        flush(index - 1);
        final end = _findDirectiveEnd(lines, index + 1);
        index = end == null ? lines.length : end + 1;
        continue;
      }

      startLineIndex ??= index;
      buffer.add(line);
      index++;
    }

    flush(lines.length - 1);
    return blocks;
  }

  int? _findDirectiveEnd(List<String> lines, int startIndex) {
    for (var index = startIndex; index < lines.length; index++) {
      if (lines[index].trim() == _directiveEnd) {
        return index;
      }
    }
    return null;
  }
}

class _AiCommandMatch {
  const _AiCommandMatch({required this.kind, this.argument});

  final AiCommandKind kind;
  final String? argument;
}

class _TextBlock {
  const _TextBlock({
    required this.startLineIndex,
    required this.endLineIndex,
    required this.text,
  });

  final int startLineIndex;
  final int endLineIndex;
  final String text;
}
