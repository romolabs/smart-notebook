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
}
