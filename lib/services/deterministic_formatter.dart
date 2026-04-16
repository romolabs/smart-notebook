import '../models/notebook_models.dart';

class DeterministicFormatter {
  const DeterministicFormatter();

  ChampionDraft buildChampionDraft(
    NoteStructure structure, {
    required ProcessorToggles toggles,
  }) {
    final renderedBlocks = <String>[];
    final changes = <EnhancementChange>[];
    var changedSpelling = false;
    var changedFormatting = false;
    var changedClarity = false;

    for (final block in structure.blocks) {
      final renderedLines = block.lines
          .map((line) {
            var rendered = _renderLine(line, toggles: toggles);
            if (toggles.spelling && rendered != line.sourceLine.trimRight()) {
              changedSpelling = true;
            }
            if (_formatChanged(line, rendered)) {
              changedFormatting = true;
            }
            if (toggles.clarity && _clarityChanged(line, rendered)) {
              changedClarity = true;
            }
            return rendered;
          })
          .toList(growable: false);
      renderedBlocks.add(renderedLines.join('\n'));
    }

    if (changedSpelling) {
      changes.add(
        const EnhancementChange(
          type: ChangeType.spelling,
          label: 'Closed-rule spelling cleanup',
          description:
              'Corrected a small set of deterministic note-taking typos without changing structure.',
        ),
      );
    }
    if (changedFormatting) {
      changes.add(
        const EnhancementChange(
          type: ChangeType.formatting,
          label: 'Structure-preserving formatting',
          description:
              'Normalized list markers, spacing, and block separation while keeping the original layout intent.',
        ),
      );
    }
    if (changedClarity) {
      changes.add(
        const EnhancementChange(
          type: ChangeType.clarity,
          label: 'Conservative clarity polish',
          description:
              'Applied low-risk punctuation and spacing cleanup without rewriting meaning.',
        ),
      );
    }

    return ChampionDraft(
      text: renderedBlocks.join('\n\n').trim(),
      structure: structure,
      changes: changes,
    );
  }

  String _renderLine(LineNode line, {required ProcessorToggles toggles}) {
    var content = line.sourceLine.trimRight();
    if (toggles.spelling) {
      content = _applyClosedSpelling(content);
    }
    if (toggles.clarity) {
      content = _applyClosedClarity(content);
    }
    if (!toggles.formatting) {
      return content;
    }

    final trimmed = content.trim();
    switch (line.kind) {
      case LineKind.heading:
        final level = line.headingLevel ?? 1;
        final title = trimmed.replaceFirst(RegExp(r'^#{1,6}\s*'), '').trim();
        return '${'#' * level} $title'.trimRight();
      case LineKind.bullet:
        final body = trimmed.replaceFirst(RegExp(r'^[-*•]\s+'), '').trim();
        return '${' ' * line.indent}- $body'.trimRight();
      case LineKind.orderedItem:
        final index = line.orderedIndex ?? 1;
        final body = trimmed.replaceFirst(RegExp(r'^\d+[.)]\s+'), '').trim();
        return '${' ' * line.indent}$index. $body'.trimRight();
      case LineKind.checkbox:
        final checked = line.checkboxChecked == true ? 'x' : ' ';
        final body = trimmed
            .replaceFirst(RegExp(r'^-\s\[( |x|X)\]\s+'), '')
            .trim();
        return '${' ' * line.indent}- [$checked] $body'.trimRight();
      case LineKind.quote:
        final body = trimmed.replaceFirst(RegExp(r'^>\s*'), '').trim();
        return '${' ' * line.indent}> $body'.trimRight();
      case LineKind.keyValue:
        final key = line.key?.trim() ?? '';
        final value =
            line.value?.trim() ??
            trimmed.replaceFirst(RegExp(r'^[^:]+:\s*'), '').trim();
        return '${' ' * line.indent}$key: $value'.trimRight();
      case LineKind.code:
        return content;
      case LineKind.tableRow:
        return trimmed;
      case LineKind.paragraph:
      case LineKind.unknown:
        return trimmed;
      case LineKind.blank:
        return '';
    }
  }

  String _applyClosedSpelling(String content) {
    var output = content;
    const boundaryReplacements = {
      r'\bteh\b': 'the',
      r'\brecieve\b': 'receive',
      r'\bseperate\b': 'separate',
      r'\bdefinately\b': 'definitely',
      r'\bdont\b': "don't",
      r'\bcant\b': "can't",
    };
    for (final entry in boundaryReplacements.entries) {
      output = output.replaceAllMapped(
        RegExp(entry.key, caseSensitive: false),
        (match) {
          final replacement = entry.value;
          return _matchCase(match.group(0)!, replacement);
        },
      );
    }
    output = output.replaceAllMapped(RegExp(r'\bw/\b'), (_) => 'with');
    return output;
  }

  String _applyClosedClarity(String content) {
    return content.replaceAll(RegExp(r'[ \t]{2,}'), ' ').replaceAllMapped(
      RegExp(r'([,;:])([^\s])'),
      (match) {
        return '${match.group(1)} ${match.group(2)}';
      },
    );
  }

  bool _formatChanged(LineNode line, String rendered) {
    if (line.kind == LineKind.code) {
      return false;
    }
    return rendered != line.sourceLine.trimRight();
  }

  bool _clarityChanged(LineNode line, String rendered) {
    if (line.kind == LineKind.code) {
      return false;
    }
    return rendered != _applyClosedSpelling(line.sourceLine.trimRight());
  }

  String _matchCase(String source, String target) {
    if (source.toUpperCase() == source) {
      return target.toUpperCase();
    }
    if (source[0].toUpperCase() == source[0]) {
      return target[0].toUpperCase() + target.substring(1);
    }
    return target;
  }
}
