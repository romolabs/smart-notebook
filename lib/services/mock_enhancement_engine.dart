import '../models/notebook_models.dart';
import 'acceptance_gate.dart';
import 'artifact_builder.dart';
import 'deterministic_formatter.dart';
import 'note_parser.dart';
import 'proposal_merger.dart';

abstract class EnhancementEngine {
  Future<EnhancementSnapshot> process(EnhancementRequest request);
}

class FormatterProcessorResult {
  const FormatterProcessorResult({
    required this.proposal,
    required this.status,
  });

  final ModelProposal proposal;
  final ProcessorStatus status;
}

class VerifierProcessorResult {
  const VerifierProcessorResult({
    required this.flags,
    required this.changes,
    required this.status,
  });

  final List<VerificationFlag> flags;
  final List<EnhancementChange> changes;
  final ProcessorStatus status;
}

abstract class LocalModelAdapter {
  const LocalModelAdapter();

  Future<FormatterProcessorResult> runFormatter({
    required EnhancementRequest request,
    required ChampionDraft champion,
  });

  Future<VerifierProcessorResult> runVerifier({
    required EnhancementRequest request,
    required String enhancedText,
  });
}

class MockEnhancementEngine implements EnhancementEngine {
  const MockEnhancementEngine({
    this.localModelAdapter = const UnavailableLocalModelAdapter(),
    this.parser = const NoteParser(),
    this.formatter = const DeterministicFormatter(),
    this.acceptanceGate = const AcceptanceGate(),
    this.artifactBuilder = const ArtifactBuilder(),
    this.proposalMerger = const ProposalMerger(),
  });

  final LocalModelAdapter localModelAdapter;
  final NoteParser parser;
  final DeterministicFormatter formatter;
  final AcceptanceGate acceptanceGate;
  final ArtifactBuilder artifactBuilder;
  final ProposalMerger proposalMerger;

  @override
  Future<EnhancementSnapshot> process(EnhancementRequest request) async {
    final normalizedRaw = request.rawContent
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    if (normalizedRaw.trim().isEmpty) {
      return _emptySnapshot();
    }

    final structure = parser.parse(
      normalizedRaw,
      revisionId: request.revisionId?.toString(),
    );
    final champion = formatter.buildChampionDraft(
      structure,
      toggles: request.toggles,
    );
    final artifacts = artifactBuilder.buildDeterministicArtifacts(
      structure: structure,
      champion: champion,
    );

    var enhancedText = champion.text;
    final changes = <EnhancementChange>[...champion.changes];
    final flags = <VerificationFlag>[];
    final processorStatuses = <ProcessorStatus>[];

    processorStatuses.add(
      await _buildFormatterStatus(
        request: request,
        champion: champion,
        onAcceptedProposals: (acceptance) {
          enhancedText = proposalMerger.merge(
            champion: champion,
            acceptedLineEdits: acceptance.acceptedLineEdits,
          );
          _mergeChanges(
            changes,
            acceptance.acceptedLineEdits
                .map(
                  (edit) => EnhancementChange(
                    type: edit.type,
                    label: edit.label,
                    description: edit.description,
                  ),
                )
                .toList(growable: false),
          );
          _mergeArtifacts(artifacts, acceptance.acceptedArtifacts);
        },
      ),
    );

    final verifierResult = _buildVerificationResult(request, normalizedRaw);
    flags.addAll(verifierResult.flags);
    _mergeChanges(changes, verifierResult.changes);
    processorStatuses.add(verifierResult.status);

    return EnhancementSnapshot(
      enhancedContent: enhancedText,
      summary: _summaryFromArtifacts(artifacts, structure.note.analysisText),
      changes: changes,
      flags: flags,
      artifacts: artifacts,
      processorStatuses: processorStatuses,
    );
  }

  EnhancementSnapshot processSync(EnhancementRequest request) {
    final normalizedRaw = request.rawContent
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    if (normalizedRaw.trim().isEmpty) {
      return _emptySnapshot();
    }

    final structure = parser.parse(
      normalizedRaw,
      revisionId: request.revisionId?.toString(),
    );
    final champion = formatter.buildChampionDraft(
      structure,
      toggles: request.toggles,
    );
    final verification = _buildVerificationResult(request, normalizedRaw);
    final artifacts = artifactBuilder.buildDeterministicArtifacts(
      structure: structure,
      champion: champion,
    );

    return EnhancementSnapshot(
      enhancedContent: champion.text,
      summary: _summaryFromArtifacts(artifacts, structure.note.analysisText),
      changes: [...champion.changes, ...verification.changes],
      flags: verification.flags,
      artifacts: artifacts,
      processorStatuses: [
        if (request.toggles.spelling ||
            request.toggles.formatting ||
            request.toggles.clarity)
          const ProcessorStatus(
            kind: ProcessorKind.formatter,
            state: ProcessorState.unavailable,
            label: 'Formatter',
            detail:
                'Seed snapshot used the deterministic structure-first champion draft.',
          )
        else
          const ProcessorStatus(
            kind: ProcessorKind.formatter,
            state: ProcessorState.skipped,
            label: 'Formatter',
            detail: 'Formatter processors are turned off.',
          ),
        verification.status,
      ],
    );
  }

  Future<ProcessorStatus> _buildFormatterStatus({
    required EnhancementRequest request,
    required ChampionDraft champion,
    required void Function(ProposalAcceptanceResult acceptance)
    onAcceptedProposals,
  }) async {
    final formatterEnabled =
        request.toggles.spelling ||
        request.toggles.formatting ||
        request.toggles.clarity;
    if (!formatterEnabled) {
      return const ProcessorStatus(
        kind: ProcessorKind.formatter,
        state: ProcessorState.skipped,
        label: 'Formatter',
        detail: 'Formatter processors are turned off.',
      );
    }

    if (request.modelMode != ModelMode.localFast) {
      return const ProcessorStatus(
        kind: ProcessorKind.formatter,
        state: ProcessorState.unavailable,
        label: 'Formatter',
        detail:
            'Cloud proposal routing is not wired yet, so the engine kept the deterministic champion draft.',
      );
    }

    final modelResult = await localModelAdapter.runFormatter(
      request: request,
      champion: champion,
    );
    if (modelResult.status.state != ProcessorState.completed) {
      return ProcessorStatus(
        kind: ProcessorKind.formatter,
        state: modelResult.status.state,
        label: 'Formatter',
        detail:
            '${modelResult.status.detail} The engine kept the deterministic champion draft.',
      );
    }

    final acceptance = acceptanceGate.evaluateLineEditProposals(
      champion: champion,
      proposal: modelResult.proposal,
    );
    if (acceptance.acceptedLineEdits.isEmpty &&
        acceptance.acceptedArtifacts.isEmpty) {
      final reason = acceptance.issues.isEmpty
          ? 'the trust gate rejected every proposed edit.'
          : acceptance.issues.first.message;
      return ProcessorStatus(
        kind: ProcessorKind.formatter,
        state: ProcessorState.completed,
        label: 'Formatter',
        detail:
            'Built the deterministic champion draft locally. No bounded model edits were accepted because $reason',
      );
    }

    onAcceptedProposals(acceptance);
    final rejectedCount =
        (modelResult.proposal.lineEdits.length -
            acceptance.acceptedLineEdits.length) +
        (modelResult.proposal.artifacts.length -
            acceptance.acceptedArtifacts.length);
    final acceptedCount =
        acceptance.acceptedLineEdits.length +
        acceptance.acceptedArtifacts.length;
    return ProcessorStatus(
      kind: ProcessorKind.formatter,
      state: ProcessorState.completed,
      label: 'Formatter',
      detail:
          'Built the deterministic champion draft and merged $acceptedCount trust-gated proposal item(s) through the engine renderer.${rejectedCount > 0 ? ' Rejected $rejectedCount item(s) that did not pass the gate.' : ''}',
    );
  }

  VerifierProcessorResult _buildVerificationResult(
    EnhancementRequest request,
    String rawContent,
  ) {
    if (!request.toggles.verification) {
      return const VerifierProcessorResult(
        flags: [],
        changes: [],
        status: ProcessorStatus(
          kind: ProcessorKind.verifier,
          state: ProcessorState.skipped,
          label: 'Verifier',
          detail: 'Verification is turned off.',
        ),
      );
    }

    final flags = _detectVerificationFlags(rawContent);
    final changes = flags.isEmpty
        ? const <EnhancementChange>[]
        : const [
            EnhancementChange(
              type: ChangeType.verification,
              label: 'Review hints',
              description:
                  'Flagged specific claims that may deserve a source check before sharing.',
            ),
          ];

    final status = request.modelMode == ModelMode.localFast
        ? const ProcessorStatus(
            kind: ProcessorKind.verifier,
            state: ProcessorState.completed,
            label: 'Verifier',
            detail:
                'Used calm deterministic review hints so local verification stays conservative.',
          )
        : const ProcessorStatus(
            kind: ProcessorKind.verifier,
            state: ProcessorState.unavailable,
            label: 'Verifier',
            detail:
                'Cloud verification is not wired yet, so the engine used deterministic review hints.',
          );

    return VerifierProcessorResult(
      flags: flags,
      changes: changes,
      status: status,
    );
  }

  void _mergeChanges(
    List<EnhancementChange> destination,
    List<EnhancementChange> incoming,
  ) {
    for (final change in incoming) {
      final exists = destination.any(
        (existing) =>
            existing.type == change.type &&
            existing.label == change.label &&
            existing.description == change.description,
      );
      if (!exists) {
        destination.add(change);
      }
    }
  }

  void _mergeArtifacts(
    List<ArtifactProposal> destination,
    List<ArtifactProposal> incoming,
  ) {
    for (final artifact in incoming) {
      final existingIndex = destination.indexWhere(
        (current) => current.kind == artifact.kind,
      );
      if (existingIndex >= 0) {
        destination[existingIndex] = artifact;
      } else {
        destination.add(artifact);
      }
    }
  }

  EnhancementSnapshot _emptySnapshot() {
    return const EnhancementSnapshot(
      enhancedContent: 'Your enhanced note will appear here as you type.',
      summary:
          'Start writing in the raw pane to see structure, cleanup, and review hints.',
      changes: [],
      flags: [],
      artifacts: [],
      processorStatuses: [
        ProcessorStatus(
          kind: ProcessorKind.formatter,
          state: ProcessorState.skipped,
          label: 'Formatter',
          detail: 'Waiting for note content.',
        ),
        ProcessorStatus(
          kind: ProcessorKind.verifier,
          state: ProcessorState.skipped,
          label: 'Verifier',
          detail: 'Waiting for note content.',
        ),
      ],
    );
  }

  List<VerificationFlag> _detectVerificationFlags(String input) {
    final flags = <VerificationFlag>[];
    final lower = input.toLowerCase();

    if (RegExp(r'\b20\d{2}\b').hasMatch(input) || lower.contains('next year')) {
      flags.add(
        const VerificationFlag(
          status: VerificationStatus.warning,
          claimText: 'Timeline or date claim',
          note:
              'Dates can drift quickly. Confirm the current timing before using this as a decision record.',
          confidence: 0.43,
        ),
      );
    }

    final numbers = RegExp(r'\b\d{3,}(?:\.\d+)?\b').allMatches(input).length;
    if (numbers > 0) {
      flags.add(
        const VerificationFlag(
          status: VerificationStatus.needsReview,
          claimText: 'Numeric claim detected',
          note:
              'Large numbers and metrics usually need a source, slide, or meeting artifact behind them.',
          confidence: 0.59,
        ),
      );
    }

    if (RegExp(
      r'\b(according to|research says|study shows)\b',
      caseSensitive: false,
    ).hasMatch(input)) {
      flags.add(
        const VerificationFlag(
          status: VerificationStatus.warning,
          claimText: 'External source claim',
          note:
              'This sounds sourced, but the note does not include the citation yet.',
          confidence: 0.71,
        ),
      );
    }

    return flags;
  }

  String _buildSummary(String input) {
    final sentences = input
        .split(RegExp(r'[\n\.]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .take(2)
        .toList(growable: false);

    if (sentences.isEmpty) {
      return 'No summary yet.';
    }

    return sentences.join(' ').trim();
  }

  String _summaryFromArtifacts(List<ArtifactProposal> artifacts, String input) {
    final summaryArtifact = artifacts
        .where((artifact) => artifact.kind == ArtifactKind.summary)
        .firstOrNull;
    return summaryArtifact?.value ?? _buildSummary(input);
  }
}

class UnavailableLocalModelAdapter extends LocalModelAdapter {
  const UnavailableLocalModelAdapter();

  @override
  Future<FormatterProcessorResult> runFormatter({
    required EnhancementRequest request,
    required ChampionDraft champion,
  }) async {
    return const FormatterProcessorResult(
      proposal: ModelProposal(),
      status: ProcessorStatus(
        kind: ProcessorKind.formatter,
        state: ProcessorState.unavailable,
        label: 'Formatter',
        detail: 'No local model runtime detected.',
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
        state: ProcessorState.unavailable,
        label: 'Verifier',
        detail: 'No local model runtime detected.',
      ),
    );
  }
}
