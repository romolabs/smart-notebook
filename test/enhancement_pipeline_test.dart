import 'package:flutter_test/flutter_test.dart';
import 'package:smart_notebook/models/notebook_models.dart';
import 'package:smart_notebook/services/acceptance_gate.dart';
import 'package:smart_notebook/services/deterministic_formatter.dart';
import 'package:smart_notebook/services/mock_enhancement_engine.dart';
import 'package:smart_notebook/services/note_parser.dart';
import 'package:smart_notebook/services/proposal_merger.dart';

void main() {
  const parser = NoteParser();
  const formatter = DeterministicFormatter();
  const gate = AcceptanceGate();
  const merger = ProposalMerger();
  const toggles = ProcessorToggles(
    spelling: true,
    formatting: true,
    clarity: true,
    verification: true,
  );

  test(
    'deterministic formatter preserves structure without inventing sections',
    () {
      final structure = parser.parse('''
meeting notes
- first draft
* second draft
- [x] ship beta
2) email team
''');

      final champion = formatter.buildChampionDraft(
        structure,
        toggles: toggles,
      );

      expect(champion.text, isNot(contains('# Enhanced Note')));
      expect(champion.text, contains('- first draft'));
      expect(champion.text, contains('- second draft'));
      expect(champion.text, contains('- [x] ship beta'));
      expect(champion.text, contains('2. email team'));
    },
  );

  test('acceptance gate rejects structure-breaking formatter drafts', () {
    final champion = formatter.buildChampionDraft(
      parser.parse('''
Title: roadmap
1) ship beta
2) email team
'''),
      toggles: toggles,
    );

    final report = gate.evaluateFormatterCandidate(
      champion: champion,
      candidateText: '''
# Enhanced Note
- ship beta soon
''',
    );

    expect(report.accepted, isFalse);
    expect(
      report.issues.map((issue) => issue.code),
      containsAll([
        'block_structure_changed',
        'line_structure_changed',
        'ordered_count_changed',
        'protected_tokens_missing',
      ]),
    );
  });

  test('acceptance gate only accepts bounded trust-first line edits', () {
    final champion = formatter.buildChampionDraft(
      parser.parse(
        ['Agenda', '- call alice at 3', '- recap blockers'].join('\n'),
      ),
      toggles: toggles,
    );

    const proposal = ModelProposal(
      lineEdits: [
        LineEditProposal(
          lineIndex: 1,
          replacement: '- call Alice at 3 pm',
          type: ChangeType.clarity,
          label: 'Tighten follow-up wording',
          description:
              'Keeps the original bullet intact while adding a small detail.',
        ),
        LineEditProposal(
          lineIndex: 2,
          replacement:
              '- recap blockers with a detailed explanation covering every dependency, owner, timeline, mitigation, follow-up, and contingency note',
          type: ChangeType.clarity,
          label: 'Expand blockers',
          description:
              'Attempts a rewrite that should be rejected as too large.',
        ),
      ],
    );

    final result = gate.evaluateLineEditProposals(
      champion: champion,
      proposal: proposal,
    );

    expect(result.acceptedLineEdits.map((edit) => edit.lineIndex), [1]);
    expect(result.acceptedLineEdits.single.replacement, '- call Alice at 3 pm');
    expect(
      result.issues.map((issue) => issue.code),
      contains('edit_too_large_2'),
    );
  });

  test('acceptance gate only accepts artifacts backed by source evidence', () {
    final champion = formatter.buildChampionDraft(
      parser.parse(
        ['Project sync', '- budget 1200', '- email Alex'].join('\n'),
      ),
      toggles: toggles,
    );

    const proposal = ModelProposal(
      artifacts: [
        ArtifactProposal(
          kind: ArtifactKind.summary,
          value: 'Budget is 1200 and Alex needs a follow-up.',
          evidenceLineIndexes: [1, 2],
          label: 'Evidence-backed summary',
          description: 'Summarizes claims already present in the source note.',
        ),
        ArtifactProposal(
          kind: ArtifactKind.title,
          value: 'Executive recap',
          evidenceLineIndexes: [],
          label: 'Unsupported title',
          description: 'Missing evidence should fail the trust gate.',
        ),
        ArtifactProposal(
          kind: ArtifactKind.summary,
          value: 'Budget is trending higher than last week.',
          evidenceLineIndexes: [99],
          label: 'Out-of-range summary',
          description: 'References a line that does not exist in the note.',
        ),
      ],
    );

    final result = gate.evaluateLineEditProposals(
      champion: champion,
      proposal: proposal,
    );

    expect(
      result.acceptedArtifacts.map((artifact) => artifact.label).toList(),
      ['Evidence-backed summary'],
    );
    expect(result.acceptedArtifacts.single.kind, ArtifactKind.summary);
    expect(
      result.issues.map((issue) => issue.code),
      containsAll([
        'artifact_missing_evidence_title',
        'artifact_missing_evidence_summary',
      ]),
    );
  });

  test('proposal merger applies accepted edits by champion line order', () {
    final champion = formatter.buildChampionDraft(
      parser.parse(
        [
          'Sprint plan',
          'capture owners',
          '',
          '- call alice at 3',
          '2) email team',
        ].join('\n'),
      ),
      toggles: toggles,
    );

    final merged = merger.merge(
      champion: champion,
      acceptedLineEdits: const [
        LineEditProposal(
          lineIndex: 4,
          replacement: '2. email team today',
          type: ChangeType.clarity,
          label: 'Clarify follow-up',
          description: 'Adds timing without changing ordered structure.',
        ),
        LineEditProposal(
          lineIndex: 1,
          replacement: 'capture owners and next steps',
          type: ChangeType.clarity,
          label: 'Clarify paragraph',
          description: 'Extends the paragraph line with the missing outcome.',
        ),
        LineEditProposal(
          lineIndex: 3,
          replacement: '- call Alice at 3 pm',
          type: ChangeType.clarity,
          label: 'Tighten bullet',
          description: 'Adds a small timing detail to the bullet line.',
        ),
      ],
    );

    expect(
      merged,
      [
        'Sprint plan',
        'capture owners and next steps',
        '',
        '- call Alice at 3 pm',
        '',
        '2. email team today',
      ].join('\n'),
    );
  });

  test(
    'engine keeps deterministic champion and sidecars when cloud routing is unavailable',
    () async {
      const rawContent = 'Project sync\n- email Alex\n- call Sam';
      final champion = formatter.buildChampionDraft(
        parser.parse(rawContent),
        toggles: toggles,
      );
      const engine = MockEnhancementEngine(
        localModelAdapter: _ThrowingLocalModelAdapter(),
      );

      final snapshot = await engine.process(
        const EnhancementRequest(
          rawContent: rawContent,
          modelMode: ModelMode.cloudAccurate,
          toggles: toggles,
        ),
      );

      expect(snapshot.enhancedContent, champion.text);
      expect(snapshot.summary, 'Project sync email Alex');
      expect(snapshot.artifacts.map((artifact) => artifact.kind).toList(), [
        ArtifactKind.title,
        ArtifactKind.summary,
        ArtifactKind.actionItems,
      ]);
      expect(
        snapshot.processorStatuses.map((status) => status.state).toList(),
        [ProcessorState.unavailable, ProcessorState.unavailable],
      );
      expect(
        snapshot.processorStatuses.first.detail,
        contains('cloud execution is not wired'),
      );
      expect(
        snapshot.processorStatuses.last.detail,
        contains('Cloud verification is not wired yet'),
      );
    },
  );

  test(
    'engine routes math-heavy notes to deterministic-only and preserves formulas',
    () async {
      const rawContent = r'''
Derivation
$$
a^2 + b^2 = c^2
$$
- email Alex
''';
      final champion = formatter.buildChampionDraft(
        parser.parse(rawContent),
        toggles: toggles,
      );
      const engine = MockEnhancementEngine(
        localModelAdapter: _ThrowingLocalModelAdapter(),
      );

      final snapshot = await engine.process(
        const EnhancementRequest(
          rawContent: rawContent,
          modelMode: ModelMode.localFast,
          toggles: toggles,
        ),
      );

      expect(snapshot.routePlan.execution, RouteExecution.deterministicOnly);
      expect(snapshot.routePlan.riskLevel, NoteRiskLevel.high);
      expect(snapshot.enhancedContent, champion.text);
      expect(snapshot.enhancedContent, contains('a^2 + b^2 = c^2'));
      expect(
        snapshot.processorStatuses.first.state,
        ProcessorState.unavailable,
      );
      expect(
        snapshot.processorStatuses.first.detail,
        contains('Deterministic-only route active'),
      );
    },
  );

  test(
    'engine falls back to deterministic champion when local formatter fails',
    () async {
      const rawContent = 'Project sync\n- budget 1200\n- call Alex';
      final champion = formatter.buildChampionDraft(
        parser.parse(rawContent),
        toggles: toggles,
      );
      const engine = MockEnhancementEngine(
        localModelAdapter: _FailedLocalModelAdapter(),
      );

      final snapshot = await engine.process(
        const EnhancementRequest(
          rawContent: rawContent,
          modelMode: ModelMode.localFast,
          toggles: toggles,
        ),
      );

      expect(snapshot.enhancedContent, champion.text);
      expect(snapshot.summary, 'Project sync budget 1200');
      expect(
        snapshot.processorStatuses.map((status) => status.state).toList(),
        [ProcessorState.failed, ProcessorState.completed],
      );
      expect(
        snapshot.processorStatuses.first.detail,
        contains('Local formatter timed out.'),
      );
      expect(
        snapshot.processorStatuses.first.detail,
        contains('The engine kept the deterministic champion draft.'),
      );
      expect(
        snapshot.flags.map((flag) => flag.claimText),
        contains('Numeric claim detected'),
      );
    },
  );
}

class _ThrowingLocalModelAdapter extends LocalModelAdapter {
  const _ThrowingLocalModelAdapter();

  @override
  Future<FormatterProcessorResult> runFormatter({
    required EnhancementRequest request,
    required ChampionDraft champion,
    required RoutePlan routePlan,
  }) {
    throw StateError(
      'Cloud routing should bypass the local formatter adapter.',
    );
  }

  @override
  Future<VerifierProcessorResult> runVerifier({
    required EnhancementRequest request,
    required String enhancedText,
  }) {
    throw StateError('Cloud routing should bypass the local verifier adapter.');
  }
}

class _FailedLocalModelAdapter extends LocalModelAdapter {
  const _FailedLocalModelAdapter();

  @override
  Future<FormatterProcessorResult> runFormatter({
    required EnhancementRequest request,
    required ChampionDraft champion,
    required RoutePlan routePlan,
  }) async {
    return const FormatterProcessorResult(
      proposal: ModelProposal(),
      status: ProcessorStatus(
        kind: ProcessorKind.formatter,
        state: ProcessorState.failed,
        label: 'Formatter',
        detail: 'Local formatter timed out.',
      ),
    );
  }

  @override
  Future<VerifierProcessorResult> runVerifier({
    required EnhancementRequest request,
    required String enhancedText,
  }) async {
    return const VerifierProcessorResult(
      flags: [],
      changes: [],
      status: ProcessorStatus(
        kind: ProcessorKind.verifier,
        state: ProcessorState.completed,
        label: 'Verifier',
        detail: 'Unused in this fallback regression test.',
      ),
    );
  }
}
