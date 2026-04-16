import '../models/notebook_models.dart';

class NoteParser {
  const NoteParser();

  NoteStructure parse(String rawText, {String? revisionId}) {
    final normalized = _normalize(rawText, revisionId: revisionId);
    final sourceLines = normalized.analysisText.split('\n');
    final lines = <LineNode>[];
    final protectedTokens = <String>{};

    var inCodeFence = false;
    for (var index = 0; index < sourceLines.length; index++) {
      final line = sourceLines[index];
      final trimmed = line.trim();
      final kind = _classifyLine(trimmed, inCodeFence: inCodeFence);
      if (trimmed.startsWith('```')) {
        inCodeFence = !inCodeFence;
      }

      final node = LineNode(
        index: index,
        sourceLine: line,
        trimmed: trimmed,
        kind: kind,
        indent: line.length - line.trimLeft().length,
        headingLevel: _headingLevel(trimmed),
        orderedIndex: _orderedIndex(trimmed),
        checkboxChecked: _checkboxChecked(trimmed),
        key: _key(trimmed),
        value: _value(trimmed),
      );
      lines.add(node);
      protectedTokens.addAll(_extractProtectedTokens(line));
    }

    final blocks = _buildBlocks(lines);
    final metrics = _buildMetrics(lines, blocks);

    return NoteStructure(
      note: normalized,
      lines: lines,
      blocks: blocks,
      metrics: metrics,
      protectedTokens: protectedTokens,
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

  LineKind _classifyLine(String trimmed, {required bool inCodeFence}) {
    if (trimmed.isEmpty) {
      return LineKind.blank;
    }
    if (inCodeFence || trimmed.startsWith('```')) {
      return LineKind.code;
    }
    if (RegExp(r'^#{1,6}\s+').hasMatch(trimmed)) {
      return LineKind.heading;
    }
    if (RegExp(r'^-\s\[( |x|X)\]\s+').hasMatch(trimmed)) {
      return LineKind.checkbox;
    }
    if (RegExp(r'^[-*•]\s+').hasMatch(trimmed)) {
      return LineKind.bullet;
    }
    if (RegExp(r'^\d+[.)]\s+').hasMatch(trimmed)) {
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
    return LineKind.paragraph;
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

      final blockKind = _blockKindForLine(line.kind);
      final shouldFlush =
          currentKind != null &&
          (blockKind != currentKind ||
              !_canContinueBlock(currentKind!, line.kind, current));
      if (shouldFlush) {
        flush();
      }

      currentKind ??= blockKind;
      current = [...current, line];
    }

    flush();
    return blocks;
  }

  bool _canContinueBlock(
    BlockKind blockKind,
    LineKind lineKind,
    List<LineNode> current,
  ) {
    switch (blockKind) {
      case BlockKind.paragraph:
        return lineKind == LineKind.paragraph;
      case BlockKind.keyValueGroup:
        return lineKind == LineKind.keyValue;
      case BlockKind.quote:
        return lineKind == LineKind.quote;
      case BlockKind.code:
        return true;
      case BlockKind.table:
        return lineKind == LineKind.tableRow;
      case BlockKind.heading:
      case BlockKind.bulletList:
      case BlockKind.orderedList:
      case BlockKind.checklist:
      case BlockKind.blank:
      case BlockKind.mixed:
        return false;
    }
  }

  BlockKind _blockKindForLine(LineKind kind) {
    return switch (kind) {
      LineKind.blank => BlockKind.blank,
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

  StructureMetrics _buildMetrics(List<LineNode> lines, List<BlockNode> blocks) {
    final nonBlank = lines
        .where((line) => !line.isBlank)
        .toList(growable: false);
    return StructureMetrics(
      lineCount: lines.length,
      nonBlankLineCount: nonBlank.length,
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
    final match = RegExp(r'^(\d+)[.)]\s+').firstMatch(trimmed);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  bool? _checkboxChecked(String trimmed) {
    final match = RegExp(r'^-\s\[( |x|X)\]\s+').firstMatch(trimmed);
    if (match == null) {
      return null;
    }
    return match.group(1)?.toLowerCase() == 'x';
  }

  bool _isKeyValue(String trimmed) {
    final match = RegExp(r'^([^:]{1,40}):\s+(.+)$').firstMatch(trimmed);
    if (match == null) {
      return false;
    }
    return !match.group(1)!.contains(' ');
  }

  String? _key(String trimmed) {
    final match = RegExp(r'^([^:]{1,40}):\s+(.+)$').firstMatch(trimmed);
    return match?.group(1);
  }

  String? _value(String trimmed) {
    final match = RegExp(r'^([^:]{1,40}):\s+(.+)$').firstMatch(trimmed);
    return match?.group(2);
  }
}
