import '../models/notebook_models.dart';

class RoutePlanner {
  const RoutePlanner();

  RoutePlan build({
    required EnhancementRequest request,
    required NoteStructure structure,
    required ChampionDraft champion,
  }) {
    final metrics = structure.metrics;
    final riskLevel = _riskLevelFor(metrics);
    final editableLineIndexes = structure.lines
        .where((line) => line.isEditable)
        .map((line) => line.index)
        .toList(growable: false);
    final mathLineIndexes = structure.lines
        .where(
          (line) =>
              line.protectedSpans.any((span) => span.kind != SpanKind.code),
        )
        .map((line) => line.index)
        .toList(growable: false);

    final allowedCapabilities = <RouteCapability>[
      if (_allowsLineEdits(request, riskLevel, editableLineIndexes))
        RouteCapability.lineEdits,
      if (_allowsTitle(request, structure)) RouteCapability.titleSuggestion,
      if (_allowsSummary(request, structure)) RouteCapability.summarySuggestion,
      if (_allowsActionItems(request, champion)) RouteCapability.actionItems,
    ];

    final execution = _executionFor(
      request: request,
      riskLevel: riskLevel,
      allowedCapabilities: allowedCapabilities,
    );

    return RoutePlan(
      execution: execution,
      riskLevel: riskLevel,
      summary: _summaryFor(
        request: request,
        execution: execution,
        riskLevel: riskLevel,
        metrics: metrics,
      ),
      allowedCapabilities: execution == RouteExecution.local
          ? allowedCapabilities
          : allowedCapabilities
                .where((capability) => capability != RouteCapability.lineEdits)
                .toList(growable: false),
      editableLineIndexes: execution == RouteExecution.local
          ? editableLineIndexes
          : const [],
      mathLineIndexes: mathLineIndexes,
      mathDensity: metrics.mathDensity,
      lockedLineRatio: metrics.lockedLineRatio,
    );
  }

  NoteRiskLevel _riskLevelFor(StructureMetrics metrics) {
    if (metrics.mathDensity >= 0.35 ||
        metrics.lockedLineRatio >= 0.35 ||
        metrics.mathLineCount >= 3) {
      return NoteRiskLevel.high;
    }
    if (metrics.mathDensity > 0 ||
        metrics.lockedLineRatio > 0 ||
        metrics.protectedSpanCount > 0) {
      return NoteRiskLevel.medium;
    }
    return NoteRiskLevel.low;
  }

  bool _allowsLineEdits(
    EnhancementRequest request,
    NoteRiskLevel riskLevel,
    List<int> editableLineIndexes,
  ) {
    if (request.modelMode != ModelMode.localFast) {
      return false;
    }
    if (!(request.toggles.spelling ||
        request.toggles.formatting ||
        request.toggles.clarity)) {
      return false;
    }
    if (riskLevel != NoteRiskLevel.low) {
      return false;
    }
    return editableLineIndexes.isNotEmpty;
  }

  bool _allowsTitle(EnhancementRequest request, NoteStructure structure) {
    return request.modelMode == ModelMode.localFast &&
        structure.lines.any((line) => !line.isBlank);
  }

  bool _allowsSummary(EnhancementRequest request, NoteStructure structure) {
    return request.modelMode == ModelMode.localFast &&
        structure.lines.where((line) => !line.isBlank).length >= 2;
  }

  bool _allowsActionItems(EnhancementRequest request, ChampionDraft champion) {
    if (request.modelMode != ModelMode.localFast) {
      return false;
    }
    return champion.structure.lines.any((line) {
      final text =
          champion.renderedLinesBySourceIndex[line.index] ?? line.trimmed;
      final normalized = text
          .toLowerCase()
          .replaceFirst(RegExp(r'^- \[[ xX]\]\s*'), '')
          .replaceFirst(RegExp(r'^-\s*'), '')
          .trim();
      return normalized.startsWith('need to ') ||
          normalized.startsWith('should ') ||
          normalized.startsWith('email ') ||
          normalized.startsWith('call ') ||
          line.kind == LineKind.checkbox;
    });
  }

  RouteExecution _executionFor({
    required EnhancementRequest request,
    required NoteRiskLevel riskLevel,
    required List<RouteCapability> allowedCapabilities,
  }) {
    if (request.modelMode == ModelMode.cloudAccurate) {
      return RouteExecution.deferredCloud;
    }
    return RouteExecution.deterministicOnly;
  }

  String _summaryFor({
    required EnhancementRequest request,
    required RouteExecution execution,
    required NoteRiskLevel riskLevel,
    required StructureMetrics metrics,
  }) {
    final mathSummary =
        'math density ${metrics.mathDensity.toStringAsFixed(2)}, locked ratio ${metrics.lockedLineRatio.toStringAsFixed(2)}';
    if (request.modelMode == ModelMode.cloudAccurate) {
      return 'Cloud route preferred for this note; current build is staying deterministic while cloud execution is not wired ($mathSummary).';
    }
    return switch (execution) {
      RouteExecution.local =>
        'Local bounded route active with ${riskLevel.name} risk ($mathSummary).',
      RouteExecution.deterministicOnly =>
        'Deterministic-only route active. Use explicit // AI commands for on-demand assistance ($mathSummary).',
      RouteExecution.deferredCloud =>
        'Cloud route deferred while current build stays deterministic ($mathSummary).',
    };
  }
}
