import '../models/notebook_models.dart';
import 'note_parser.dart';

class AcceptanceGate {
  const AcceptanceGate({this.parser = const NoteParser()});

  final NoteParser parser;

  AcceptanceReport evaluateFormatterCandidate({
    required ChampionDraft champion,
    required String candidateText,
  }) {
    final trimmedCandidate = candidateText.trim();
    if (trimmedCandidate.isEmpty) {
      return const AcceptanceReport(
        decision: AcceptanceDecision.rejected,
        issues: [
          AcceptanceIssue(
            code: 'empty_candidate',
            message: 'Model returned an empty draft.',
          ),
        ],
      );
    }

    final candidateStructure = parser.parse(trimmedCandidate);
    final issues = <AcceptanceIssue>[];
    final championMetrics = champion.structure.metrics;
    final candidateMetrics = candidateStructure.metrics;

    if (!_sameBlockKinds(champion.structure, candidateStructure)) {
      issues.add(
        const AcceptanceIssue(
          code: 'block_structure_changed',
          message: 'Block structure changed from the deterministic champion.',
        ),
      );
    }

    if (!_sameLineKinds(champion.structure, candidateStructure)) {
      issues.add(
        const AcceptanceIssue(
          code: 'line_structure_changed',
          message:
              'Line kinds or line order changed from the deterministic champion.',
        ),
      );
    }

    if (candidateMetrics.headingCount < championMetrics.headingCount) {
      issues.add(
        const AcceptanceIssue(
          code: 'heading_drop',
          message: 'Candidate removed one or more headings.',
        ),
      );
    }

    if (candidateMetrics.orderedItemCount != championMetrics.orderedItemCount) {
      issues.add(
        const AcceptanceIssue(
          code: 'ordered_count_changed',
          message: 'Candidate changed the ordered list item count.',
        ),
      );
    }

    if (candidateMetrics.checkboxCount != championMetrics.checkboxCount ||
        candidateMetrics.checkedCheckboxCount !=
            championMetrics.checkedCheckboxCount) {
      issues.add(
        const AcceptanceIssue(
          code: 'checkbox_state_changed',
          message: 'Candidate changed checklist count or checkbox state.',
        ),
      );
    }

    final missingTokens = champion.structure.protectedTokens
        .where((token) => !candidateStructure.protectedTokens.contains(token))
        .take(5)
        .toList(growable: false);
    if (missingTokens.isNotEmpty) {
      issues.add(
        AcceptanceIssue(
          code: 'protected_tokens_missing',
          message:
              'Candidate dropped protected tokens: ${missingTokens.join(', ')}',
        ),
      );
    }

    final introducedTokens = candidateStructure.protectedTokens
        .difference(champion.structure.protectedTokens)
        .where(_isRiskyNewToken)
        .take(5)
        .toList(growable: false);
    if (introducedTokens.isNotEmpty) {
      issues.add(
        AcceptanceIssue(
          code: 'new_protected_tokens',
          message:
              'Candidate introduced new structured tokens: ${introducedTokens.join(', ')}',
        ),
      );
    }

    if (issues.isNotEmpty) {
      return AcceptanceReport(
        decision: AcceptanceDecision.rejected,
        issues: issues,
      );
    }

    return AcceptanceReport(
      decision: AcceptanceDecision.accepted,
      issues: const [],
      acceptedText: trimmedCandidate,
    );
  }

  ProposalAcceptanceResult evaluateLineEditProposals({
    required ChampionDraft champion,
    required ModelProposal proposal,
  }) {
    final acceptedLineEdits = <LineEditProposal>[];
    final acceptedArtifacts = <ArtifactProposal>[];
    final issues = <AcceptanceIssue>[];

    for (final lineEdit in proposal.lineEdits) {
      final line = champion.structure.lines
          .where((candidate) => candidate.index == lineEdit.lineIndex)
          .firstOrNull;
      if (line == null) {
        issues.add(
          AcceptanceIssue(
            code: 'unknown_line_${lineEdit.lineIndex}',
            message:
                'Proposal referenced a missing line index ${lineEdit.lineIndex}.',
          ),
        );
        continue;
      }

      final replacement = lineEdit.replacement.trim();
      if (replacement.isEmpty || replacement.contains('\n')) {
        issues.add(
          AcceptanceIssue(
            code: 'invalid_replacement_${lineEdit.lineIndex}',
            message:
                'Proposal for line ${lineEdit.lineIndex} must stay a single non-empty line.',
          ),
        );
        continue;
      }

      if ({
        LineKind.blank,
        LineKind.code,
        LineKind.heading,
        LineKind.tableRow,
      }.contains(line.kind)) {
        issues.add(
          AcceptanceIssue(
            code: 'protected_line_kind_${lineEdit.lineIndex}',
            message:
                'Line ${lineEdit.lineIndex} is a protected ${line.kind.name} line and cannot be model-edited yet.',
          ),
        );
        continue;
      }

      final replacementNode = parser.parse(replacement).lines.firstOrNull;
      if (replacementNode == null || replacementNode.kind != line.kind) {
        issues.add(
          AcceptanceIssue(
            code: 'line_kind_changed_${lineEdit.lineIndex}',
            message:
                'Proposal for line ${lineEdit.lineIndex} changed the line kind from ${line.kind.name}.',
          ),
        );
        continue;
      }

      if (line.kind == LineKind.checkbox &&
          replacementNode.checkboxChecked != line.checkboxChecked) {
        issues.add(
          AcceptanceIssue(
            code: 'checkbox_state_changed_${lineEdit.lineIndex}',
            message:
                'Proposal for line ${lineEdit.lineIndex} changed checkbox state.',
          ),
        );
        continue;
      }

      if (line.kind == LineKind.orderedItem &&
          replacementNode.orderedIndex != line.orderedIndex) {
        issues.add(
          AcceptanceIssue(
            code: 'ordered_index_changed_${lineEdit.lineIndex}',
            message:
                'Proposal for line ${lineEdit.lineIndex} changed the ordered list index.',
          ),
        );
        continue;
      }

      final sourceTokens = parser
          .parse(
            champion.renderedLinesBySourceIndex[line.index] ?? line.sourceLine,
          )
          .protectedTokens;
      final replacementTokens = parser.parse(replacement).protectedTokens;
      final missingTokens = sourceTokens
          .where((token) => !replacementTokens.contains(token))
          .toList(growable: false);
      if (missingTokens.isNotEmpty) {
        issues.add(
          AcceptanceIssue(
            code: 'missing_tokens_${lineEdit.lineIndex}',
            message:
                'Proposal for line ${lineEdit.lineIndex} dropped protected tokens: ${missingTokens.join(', ')}',
          ),
        );
        continue;
      }

      final newTokens = replacementTokens
          .difference(sourceTokens)
          .where(_isRiskyNewToken)
          .toList(growable: false);
      if (newTokens.isNotEmpty) {
        issues.add(
          AcceptanceIssue(
            code: 'new_tokens_${lineEdit.lineIndex}',
            message:
                'Proposal for line ${lineEdit.lineIndex} introduced new protected tokens: ${newTokens.join(', ')}',
          ),
        );
        continue;
      }

      final originalLength =
          (champion.renderedLinesBySourceIndex[line.index] ??
                  line.sourceLine.trimRight())
              .length;
      final replacementLength = replacement.length;
      final lengthDelta = (replacementLength - originalLength).abs();
      if (lengthDelta > 60 ||
          replacementLength > (originalLength * 1.8).ceil()) {
        issues.add(
          AcceptanceIssue(
            code: 'edit_too_large_${lineEdit.lineIndex}',
            message:
                'Proposal for line ${lineEdit.lineIndex} is too large for a bounded edit.',
          ),
        );
        continue;
      }

      acceptedLineEdits.add(
        LineEditProposal(
          lineIndex: lineEdit.lineIndex,
          replacement: replacement,
          type: lineEdit.type,
          label: lineEdit.label,
          description: lineEdit.description,
        ),
      );
    }

    for (final artifact in proposal.artifacts) {
      if (_artifactHasEvidence(artifact, champion.structure)) {
        acceptedArtifacts.add(artifact);
      } else {
        issues.add(
          AcceptanceIssue(
            code: 'artifact_missing_evidence_${artifact.kind.name}',
            message:
                'Artifact proposal "${artifact.label}" does not cite valid source lines.',
          ),
        );
      }
    }

    return ProposalAcceptanceResult(
      acceptedLineEdits: acceptedLineEdits,
      acceptedArtifacts: acceptedArtifacts,
      issues: issues,
    );
  }

  bool _sameLineKinds(NoteStructure left, NoteStructure right) {
    if (left.lines.length != right.lines.length) {
      return false;
    }

    for (var index = 0; index < left.lines.length; index++) {
      if (left.lines[index].kind != right.lines[index].kind) {
        return false;
      }
    }
    return true;
  }

  bool _sameBlockKinds(NoteStructure left, NoteStructure right) {
    if (left.blocks.length != right.blocks.length) {
      return false;
    }

    for (var index = 0; index < left.blocks.length; index++) {
      if (left.blocks[index].kind != right.blocks[index].kind) {
        return false;
      }
    }
    return true;
  }

  bool _isRiskyNewToken(String token) {
    return RegExp(
      r'(^https?://)|(@)|(\b\d+(?:\.\d+)?\b)|(:)|(\.dart$)|(\.md$)|(\.json$)',
    ).hasMatch(token);
  }

  bool _artifactHasEvidence(
    ArtifactProposal artifact,
    NoteStructure structure,
  ) {
    if (artifact.evidenceLineIndexes.isEmpty) {
      return false;
    }

    final lineIndexes = structure.lines.map((line) => line.index).toSet();
    return artifact.evidenceLineIndexes.every(lineIndexes.contains);
  }
}
