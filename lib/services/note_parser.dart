import '../models/notebook_models.dart';

class NoteParser {
  const NoteParser();

  static const _mathDirectiveStart = '/math';
  static const _directiveEnd = '/end';

  static final RegExp _headingPattern = RegExp(r'^#{1,6}\s+');
  static final RegExp _checkboxPattern = RegExp(r'^-\s\[( |x|X)\]\s+');
  static final RegExp _bulletPattern = RegExp(r'^[-*•]\s+');
  static final RegExp _orderedPattern = RegExp(r'^(\d+)[.)]\s+');
  static final RegExp _keyValuePattern = RegExp(r'^([^:]{1,40}):\s+(.+)$');
  static final RegExp _latexCommandPattern = RegExp(r'\\[A-Za-z]+\\*?');
  static final RegExp _asciiMathPattern = RegExp(
    r'(\^|_|\\frac|\\sqrt|\\sum|\\int|\\alpha|\\beta|\\theta|\\lambda)',
  );
  static final RegExp _unicodeMathPattern = RegExp(
    r'[±∓×÷·≠≤≥≈∼∝∑∏∫∂∇√∞∈∉⊂⊆∪∩∀∃∧∨¬→←↔⇒⇔↦αβγδεθλμπρστυφψω⁰¹²³⁴⁵⁶⁷⁸⁹₀₁₂₃₄₅₆₇₈₉]',
  );
  static final RegExp _relationPattern = RegExp(
    r'(=|≈|≠|≤|≥|<|>|∝|→|⇒|⇔|\\approx|\\leq|\\geq|\\to|\\Rightarrow)',
  );
  static final RegExp _currencyOnlyPattern = RegExp(r'^\$?\d[\d,]*(?:\.\d+)?$');
  static final RegExp _blockMathBeginPattern = RegExp(
    r'^\\begin\{(equation\*?|align\*?|aligned|gather|multline|cases|matrix|pmatrix|bmatrix|vmatrix|Vmatrix|array)\}',
  );
  static final RegExp _blockMathEndPattern = RegExp(r'^\\end\{([A-Za-z*]+)\}');

  NoteStructure parse(String rawText, {String? revisionId}) {
    final normalized = _normalize(rawText, revisionId: revisionId);
    final sourceLines = normalized.analysisText.split('\n');
    final lines = <LineNode>[];
    final protectedTokens = <String>{};
    final protectedSpans = <ProtectedSpan>[];

    var inCodeFence = false;
    var inBlockMath = false;
    var inDirectiveMath = false;
    String? blockMathCloser;

    for (var index = 0; index < sourceLines.length; index++) {
      final line = sourceLines[index];
      final trimmed = line.trim();
      final isMathDirectiveStart = trimmed == _mathDirectiveStart;
      final isDirectiveEnd = trimmed == _directiveEnd;
      final isMathDirectiveBoundary =
          isMathDirectiveStart || (isDirectiveEnd && inDirectiveMath);
      final lineProtectedSpans = _detectProtectedSpans(
        line: line,
        trimmed: trimmed,
        lineIndex: index,
        inCodeFence: inCodeFence,
        inBlockMath: inBlockMath,
        inDirectiveMath: inDirectiveMath,
        isMathDirectiveBoundary: isMathDirectiveBoundary,
      );
      final kind = _classifyLine(
        trimmed,
        inCodeFence: inCodeFence,
        hasProtectedMath: lineProtectedSpans.any(
          (span) => span.kind != SpanKind.code,
        ),
      );

      if (trimmed.startsWith('```')) {
        inCodeFence = !inCodeFence;
      }

      if (!inCodeFence) {
        final startedBlockMath = _blockMathStartToken(trimmed);
        if (!inBlockMath && startedBlockMath != null) {
          inBlockMath = true;
          blockMathCloser = startedBlockMath;
        } else if (inBlockMath &&
            ((blockMathCloser != null && trimmed == blockMathCloser) ||
                _matchesBlockMathEnd(trimmed, blockMathCloser))) {
          inBlockMath = false;
          blockMathCloser = null;
        }

        if (isMathDirectiveStart) {
          inDirectiveMath = true;
        } else if (isDirectiveEnd && inDirectiveMath) {
          inDirectiveMath = false;
        }
      }

      final node = LineNode(
        index: index,
        sourceLine: line,
        trimmed: trimmed,
        kind: kind,
        indent: line.length - line.trimLeft().length,
        protectedSpans: lineProtectedSpans,
        headingLevel: _headingLevel(trimmed),
        orderedIndex: _orderedIndex(trimmed),
        checkboxChecked: _checkboxChecked(trimmed),
        key: _key(trimmed),
        value: _value(trimmed),
      );
      lines.add(node);
      protectedSpans.addAll(lineProtectedSpans);
      protectedTokens.addAll(_extractProtectedTokens(line));
      for (final span in lineProtectedSpans) {
        protectedTokens.addAll(_extractProtectedTokens(span.rawText));
      }
    }

    final blocks = _buildBlocks(lines);
    final metrics = _buildMetrics(lines, blocks, protectedSpans);

    return NoteStructure(
      note: normalized,
      lines: lines,
      blocks: blocks,
      metrics: metrics,
      protectedTokens: protectedTokens,
      protectedSpans: protectedSpans,
    );
  }

  NormalizedNote _normalize(String rawText, {String? revisionId}) {
    final raw = rawText.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final analysisLines = raw
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'[ \t]+$'), ''))
        .toList(growable: false);
    final analysisText = analysisLines.join('\n');
    return NormalizedNote(
      rawText: raw,
      analysisText: analysisText,
      revisionId: revisionId ?? raw.hashCode.toUnsigned(32).toRadixString(16),
    );
  }

  LineKind _classifyLine(
    String trimmed, {
    required bool inCodeFence,
    required bool hasProtectedMath,
  }) {
    if (trimmed.isEmpty) {
      return LineKind.blank;
    }
    if (inCodeFence || trimmed.startsWith('```')) {
      return LineKind.code;
    }
    if (trimmed == _mathDirectiveStart || trimmed == _directiveEnd) {
      return LineKind.directive;
    }
    if (_headingPattern.hasMatch(trimmed)) {
      return LineKind.heading;
    }
    if (_checkboxPattern.hasMatch(trimmed)) {
      return LineKind.checkbox;
    }
    if (_bulletPattern.hasMatch(trimmed)) {
      return LineKind.bullet;
    }
    if (_orderedPattern.hasMatch(trimmed)) {
      return LineKind.orderedItem;
    }
    if (trimmed.startsWith('>')) {
      return LineKind.quote;
    }
    if (_isKeyValue(trimmed)) {
      return LineKind.keyValue;
    }
    if (trimmed.contains('|') && trimmed.split('|').length >= 3) {
      return LineKind.tableRow;
    }
    if (hasProtectedMath) {
      return LineKind.unknown;
    }
    return LineKind.paragraph;
  }

  List<ProtectedSpan> _detectProtectedSpans({
    required String line,
    required String trimmed,
    required int lineIndex,
    required bool inCodeFence,
    required bool inBlockMath,
    required bool inDirectiveMath,
    required bool isMathDirectiveBoundary,
  }) {
    if (trimmed.isEmpty) {
      return const [];
    }
    if (inCodeFence || trimmed.startsWith('```')) {
      return [
        _fullLineSpan(
          line: line,
          lineIndex: lineIndex,
          kind: SpanKind.code,
          protectionMode: ProtectionMode.exactLocked,
        ),
      ];
    }
    if (inBlockMath || _blockMathStartToken(trimmed) != null) {
      return [
        _fullLineSpan(
          line: line,
          lineIndex: lineIndex,
          kind: SpanKind.blockMathTex,
          protectionMode: inBlockMath
              ? ProtectionMode.layoutLocked
              : ProtectionMode.exactLocked,
        ),
      ];
    }
    if (inDirectiveMath || isMathDirectiveBoundary) {
      return [
        _fullLineSpan(
          line: line,
          lineIndex: lineIndex,
          kind: SpanKind.blockMathTex,
          protectionMode: ProtectionMode.exactLocked,
        ),
      ];
    }

    final spans = <ProtectedSpan>[];
    spans.addAll(_inlineMathDollarSpans(line, lineIndex));
    spans.addAll(_inlineMathParenSpans(line, lineIndex));

    if (_isEquationLine(trimmed) || _isMathHeavyLine(trimmed)) {
      return [
        _fullLineSpan(
          line: line,
          lineIndex: lineIndex,
          kind: SpanKind.equationRun,
          protectionMode: ProtectionMode.exactLocked,
        ),
      ];
    }

    if (spans.isNotEmpty) {
      return spans;
    }

    return const [];
  }

  List<ProtectedSpan> _inlineMathDollarSpans(String line, int lineIndex) {
    final spans = <ProtectedSpan>[];
    var index = 0;
    while (index < line.length) {
      final start = line.indexOf(r'$', index);
      if (start < 0) {
        break;
      }
      if (_isEscaped(line, start) ||
          (start + 1 < line.length && line[start + 1] == r'$')) {
        index = start + 1;
        continue;
      }

      final end = _findClosingDollar(line, start + 1);
      if (end < 0) {
        break;
      }

      final content = line.substring(start + 1, end).trim();
      if (content.isNotEmpty && !_currencyOnlyPattern.hasMatch(content)) {
        spans.add(
          ProtectedSpan(
            id: 'span-$lineIndex-$start-$end',
            lineIndex: lineIndex,
            start: start,
            end: end + 1,
            kind: SpanKind.inlineMathTex,
            protectionMode: ProtectionMode.exactLocked,
            rawText: line.substring(start, end + 1),
          ),
        );
      }
      index = end + 1;
    }
    return spans;
  }

  List<ProtectedSpan> _inlineMathParenSpans(String line, int lineIndex) {
    final spans = <ProtectedSpan>[];
    var index = 0;
    while (index < line.length) {
      final start = line.indexOf(r'\(', index);
      if (start < 0) {
        break;
      }
      final end = line.indexOf(r'\)', start + 2);
      if (end < 0) {
        break;
      }
      spans.add(
        ProtectedSpan(
          id: 'span-$lineIndex-$start-$end',
          lineIndex: lineIndex,
          start: start,
          end: end + 2,
          kind: SpanKind.inlineMathTex,
          protectionMode: ProtectionMode.exactLocked,
          rawText: line.substring(start, end + 2),
        ),
      );
      index = end + 2;
    }
    return spans;
  }

  int _findClosingDollar(String line, int from) {
    var index = from;
    while (index < line.length) {
      final candidate = line.indexOf(r'$', index);
      if (candidate < 0) {
        return -1;
      }
      if (!_isEscaped(line, candidate) &&
          !(candidate + 1 < line.length && line[candidate + 1] == r'$')) {
        return candidate;
      }
      index = candidate + 1;
    }
    return -1;
  }

  bool _isEscaped(String source, int index) {
    if (index == 0) {
      return false;
    }
    var slashCount = 0;
    var cursor = index - 1;
    while (cursor >= 0 && source[cursor] == r'\') {
      slashCount++;
      cursor--;
    }
    return slashCount.isOdd;
  }

  String? _blockMathStartToken(String trimmed) {
    if (trimmed == r'$$') {
      return r'$$';
    }
    if (trimmed == r'\[') {
      return r'\]';
    }
    final beginMatch = _blockMathBeginPattern.firstMatch(trimmed);
    if (beginMatch != null) {
      return r'\end{${beginMatch.group(1)}}';
    }
    return null;
  }

  bool _matchesBlockMathEnd(String trimmed, String? expected) {
    if (expected == null) {
      return false;
    }
    if (trimmed == expected) {
      return true;
    }
    final endMatch = _blockMathEndPattern.firstMatch(trimmed);
    return endMatch != null && trimmed == expected;
  }

  bool _isMathHeavyLine(String trimmed) {
    final latexCount = _latexCommandPattern.allMatches(trimmed).length;
    final hasAsciiMath = _asciiMathPattern.hasMatch(trimmed);
    final hasUnicodeMath = _unicodeMathPattern.hasMatch(trimmed);
    final hasSuperSub = trimmed.contains('^') || trimmed.contains('_');
    return latexCount >= 2 ||
        (latexCount >= 1 && (hasAsciiMath || hasUnicodeMath)) ||
        (hasUnicodeMath && hasSuperSub);
  }

  bool _isEquationLine(String trimmed) {
    final hasRelation = _relationPattern.hasMatch(trimmed);
    if (!hasRelation) {
      return false;
    }

    var signalCount = 0;
    if (_latexCommandPattern.hasMatch(trimmed)) {
      signalCount++;
    }
    if (_unicodeMathPattern.hasMatch(trimmed)) {
      signalCount++;
    }
    if (trimmed.contains('(') ||
        trimmed.contains('[') ||
        trimmed.contains('{')) {
      signalCount++;
    }
    if (trimmed.contains('^') || trimmed.contains('_')) {
      signalCount++;
    }
    if (RegExp(r'[A-Za-z]\s*[-+*/]\s*[A-Za-z0-9]').hasMatch(trimmed)) {
      signalCount++;
    }

    return signalCount >= 2;
  }

  ProtectedSpan _fullLineSpan({
    required String line,
    required int lineIndex,
    required SpanKind kind,
    required ProtectionMode protectionMode,
  }) {
    return ProtectedSpan(
      id: 'span-$lineIndex-0-${line.length}',
      lineIndex: lineIndex,
      start: 0,
      end: line.length,
      kind: kind,
      protectionMode: protectionMode,
      rawText: line,
    );
  }

  List<BlockNode> _buildBlocks(List<LineNode> lines) {
    final blocks = <BlockNode>[];
    var current = <LineNode>[];
    BlockKind? currentKind;

    void flush() {
      if (current.isEmpty || currentKind == null) {
        current = <LineNode>[];
        currentKind = null;
        return;
      }
      blocks.add(
        BlockNode(index: blocks.length, kind: currentKind!, lines: current),
      );
      current = <LineNode>[];
      currentKind = null;
    }

    for (final line in lines) {
      if (line.isBlank) {
        flush();
        continue;
      }

      final blockKind = _blockKindForLine(line);
      final shouldFlush =
          currentKind != null &&
          (blockKind != currentKind ||
              !_canContinueBlock(currentKind!, line.kind));
      if (shouldFlush) {
        flush();
      }

      currentKind ??= blockKind;
      current = [...current, line];
    }

    flush();
    return blocks;
  }

  bool _canContinueBlock(BlockKind blockKind, LineKind lineKind) {
    switch (blockKind) {
      case BlockKind.math:
        return lineKind == LineKind.directive || lineKind == LineKind.unknown;
      case BlockKind.paragraph:
        return lineKind == LineKind.paragraph;
      case BlockKind.keyValueGroup:
        return lineKind == LineKind.keyValue;
      case BlockKind.quote:
        return lineKind == LineKind.quote;
      case BlockKind.code:
      case BlockKind.mixed:
        return true;
      case BlockKind.table:
        return lineKind == LineKind.tableRow;
      case BlockKind.heading:
      case BlockKind.bulletList:
      case BlockKind.orderedList:
      case BlockKind.checklist:
      case BlockKind.blank:
        return false;
    }
  }

  BlockKind _blockKindForLine(LineNode line) {
    if (line.protectedSpans.any(
      (span) =>
          span.kind == SpanKind.blockMathTex ||
          span.kind == SpanKind.equationRun,
    )) {
      return BlockKind.math;
    }

    return switch (line.kind) {
      LineKind.blank => BlockKind.blank,
      LineKind.directive => BlockKind.math,
      LineKind.paragraph => BlockKind.paragraph,
      LineKind.bullet => BlockKind.bulletList,
      LineKind.orderedItem => BlockKind.orderedList,
      LineKind.checkbox => BlockKind.checklist,
      LineKind.heading => BlockKind.heading,
      LineKind.keyValue => BlockKind.keyValueGroup,
      LineKind.quote => BlockKind.quote,
      LineKind.code => BlockKind.code,
      LineKind.tableRow => BlockKind.table,
      LineKind.unknown => BlockKind.mixed,
    };
  }

  StructureMetrics _buildMetrics(
    List<LineNode> lines,
    List<BlockNode> blocks,
    List<ProtectedSpan> protectedSpans,
  ) {
    final nonBlank = lines
        .where((line) => !line.isBlank)
        .toList(growable: false);
    final mathLines = lines
        .where(
          (line) =>
              line.protectedSpans.any((span) => span.kind != SpanKind.code),
        )
        .length;
    final lockedLines = lines.where((line) => line.hasProtectedContent).length;
    final nonBlankCount = nonBlank.length;

    return StructureMetrics(
      lineCount: lines.length,
      nonBlankLineCount: nonBlankCount,
      blockCount: blocks.length,
      headingCount: lines.where((line) => line.kind == LineKind.heading).length,
      bulletCount: lines.where((line) => line.kind == LineKind.bullet).length,
      orderedItemCount: lines
          .where((line) => line.kind == LineKind.orderedItem)
          .length,
      checkboxCount: lines
          .where((line) => line.kind == LineKind.checkbox)
          .length,
      checkedCheckboxCount: lines
          .where(
            (line) =>
                line.kind == LineKind.checkbox && line.checkboxChecked == true,
          )
          .length,
      quoteLineCount: lines.where((line) => line.kind == LineKind.quote).length,
      codeLineCount: lines.where((line) => line.kind == LineKind.code).length,
      keyValueCount: lines
          .where((line) => line.kind == LineKind.keyValue)
          .length,
      tableRowCount: lines
          .where((line) => line.kind == LineKind.tableRow)
          .length,
      protectedSpanCount: protectedSpans.length,
      mathLineCount: mathLines,
      lockedLineCount: lockedLines,
      mathDensity: nonBlankCount == 0 ? 0 : mathLines / nonBlankCount,
      lockedLineRatio: nonBlankCount == 0 ? 0 : lockedLines / nonBlankCount,
    );
  }

  Iterable<String> _extractProtectedTokens(String line) sync* {
    final patterns = [
      RegExp(r'https?://[^\s]+'),
      RegExp(r'\b[\w\.-]+@[\w\.-]+\.\w+\b'),
      RegExp(
        r'\b[a-zA-Z0-9_-]+\.(?:dart|md|txt|json|yaml|yml|swift|kt|js|ts)\b',
      ),
      RegExp(r'\b\d{1,4}[/-]\d{1,2}[/-]\d{1,4}\b'),
      RegExp(r'\b\d+(?:\.\d+)?\b'),
      RegExp(r'\b[A-Za-z0-9_-]+:[A-Za-z0-9._-]+\b'),
      RegExp(r'`[^`]+`'),
      RegExp(r'\\[A-Za-z]+\\*?'),
      RegExp(r'[±∓×÷·≠≤≥≈∼∝∑∏∫∂∇√∞∈∉⊂⊆∪∩∀∃∧∨¬→←↔⇒⇔↦αβγδεθλμπρστυφψω]'),
    ];

    for (final pattern in patterns) {
      for (final match in pattern.allMatches(line)) {
        final token = match.group(0);
        if (token != null && token.isNotEmpty) {
          yield token;
        }
      }
    }
  }

  int? _headingLevel(String trimmed) {
    final match = RegExp(r'^(#{1,6})\s+').firstMatch(trimmed);
    return match?.group(1)?.length;
  }

  int? _orderedIndex(String trimmed) {
    final match = _orderedPattern.firstMatch(trimmed);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  bool? _checkboxChecked(String trimmed) {
    final match = _checkboxPattern.firstMatch(trimmed);
    if (match == null) {
      return null;
    }
    return match.group(1)?.toLowerCase() == 'x';
  }

  bool _isKeyValue(String trimmed) {
    final match = _keyValuePattern.firstMatch(trimmed);
    if (match == null) {
      return false;
    }
    return !match.group(1)!.contains(' ');
  }

  String? _key(String trimmed) {
    final match = _keyValuePattern.firstMatch(trimmed);
    return match?.group(1);
  }

  String? _value(String trimmed) {
    final match = _keyValuePattern.firstMatch(trimmed);
    return match?.group(2);
  }
}
