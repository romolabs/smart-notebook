import '../models/notebook_models.dart';

class ArtifactBuilder {
  const ArtifactBuilder();

  List<ArtifactProposal> buildDeterministicArtifacts({
    required NoteStructure structure,
    required ChampionDraft champion,
  }) {
    final artifacts = <ArtifactProposal>[];
    final title = _buildSuggestedTitle(structure, champion);
    if (title != null) {
      artifacts.add(title);
    }

    final summary = _buildSummary(structure, champion);
    if (summary != null) {
      artifacts.add(summary);
    }

    final actionItems = _buildActionItems(structure, champion);
    if (actionItems != null) {
      artifacts.add(actionItems);
    }

    return artifacts;
  }

  ArtifactProposal? _buildSuggestedTitle(
    NoteStructure structure,
    ChampionDraft champion,
  ) {
    final heading = structure.lines.firstWhere(
      (line) => line.kind == LineKind.heading,
      orElse: () => structure.lines.firstWhere(
        (line) => !line.isBlank,
        orElse: () => const LineNode(
          index: -1,
          sourceLine: '',
          trimmed: '',
          kind: LineKind.blank,
          indent: 0,
        ),
      ),
    );
    if (heading.index < 0) {
      return null;
    }

    final source =
        champion.renderedLinesBySourceIndex[heading.index] ?? heading.trimmed;
    final cleaned = source
        .replaceFirst(RegExp(r'^#{1,6}\s*'), '')
        .replaceFirst(RegExp(r'^[-*•]\s*'), '')
        .trim();
    if (cleaned.isEmpty) {
      return null;
    }

    final value = _truncateWords(cleaned, maxWords: 8, maxChars: 60);
    return ArtifactProposal(
      kind: ArtifactKind.title,
      value: value,
      evidenceLineIndexes: [heading.index],
      label: 'Suggested title',
      description: 'Derived conservatively from the note itself.',
    );
  }

  ArtifactProposal? _buildSummary(
    NoteStructure structure,
    ChampionDraft champion,
  ) {
    final evidenceLines = structure.lines
        .where((line) => !line.isBlank)
        .take(2)
        .toList(growable: false);
    if (evidenceLines.isEmpty) {
      return null;
    }

    final sentences = evidenceLines
        .map(
          (line) =>
              champion.renderedLinesBySourceIndex[line.index] ?? line.trimmed,
        )
        .map((line) => line.replaceFirst(RegExp(r'^[-*•]\s*'), '').trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (sentences.isEmpty) {
      return null;
    }

    return ArtifactProposal(
      kind: ArtifactKind.summary,
      value: sentences.join(' ').trim(),
      evidenceLineIndexes: evidenceLines
          .map((line) => line.index)
          .toList(growable: false),
      label: 'Summary',
      description: 'Built from the first grounded lines in the note.',
    );
  }

  ArtifactProposal? _buildActionItems(
    NoteStructure structure,
    ChampionDraft champion,
  ) {
    final candidates = structure.lines
        .where((line) {
          if (line.isBlank) {
            return false;
          }
          final text =
              (champion.renderedLinesBySourceIndex[line.index] ?? line.trimmed)
                  .toLowerCase();
          final normalized = text
              .replaceFirst(RegExp(r'^- \[[ xX]\]\s*'), '')
              .replaceFirst(RegExp(r'^-\s*'), '')
              .trim();
          if (line.kind == LineKind.checkbox) {
            return true;
          }
          return normalized.startsWith('need to ') ||
              normalized.startsWith('should ') ||
              normalized.startsWith('follow up') ||
              normalized.startsWith('email ') ||
              normalized.startsWith('call ');
        })
        .take(3)
        .toList(growable: false);

    if (candidates.isEmpty) {
      return null;
    }

    final lines = candidates
        .map((line) {
          final text =
              champion.renderedLinesBySourceIndex[line.index] ?? line.trimmed;
          if (line.kind == LineKind.checkbox) {
            return text;
          }
          return text.startsWith('- ') ? text : '- ${text.trim()}';
        })
        .toList(growable: false);

    return ArtifactProposal(
      kind: ArtifactKind.actionItems,
      value: lines.join('\n'),
      evidenceLineIndexes: candidates
          .map((line) => line.index)
          .toList(growable: false),
      label: 'Action items',
      description: 'Pulled from explicit action-oriented lines in the note.',
    );
  }

  String _truncateWords(
    String value, {
    required int maxWords,
    required int maxChars,
  }) {
    final words = value
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    final truncated = words.take(maxWords).join(' ');
    if (truncated.length <= maxChars) {
      return truncated;
    }
    return truncated.substring(0, maxChars).trimRight();
  }
}
