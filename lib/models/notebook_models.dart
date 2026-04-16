import 'dart:convert';

enum ModelMode { localFast, cloudAccurate }

enum ChangeType { spelling, formatting, clarity, verification }

enum VerificationStatus { warning, needsReview }

enum ProcessorKind { formatter, verifier }

enum ProcessorState { completed, skipped, unavailable, failed }

enum LineKind {
  blank,
  paragraph,
  bullet,
  orderedItem,
  checkbox,
  heading,
  keyValue,
  quote,
  code,
  tableRow,
  unknown,
}

enum BlockKind {
  blank,
  paragraph,
  bulletList,
  orderedList,
  checklist,
  heading,
  keyValueGroup,
  quote,
  code,
  table,
  mixed,
}

enum AcceptanceDecision { accepted, rejected }

enum ArtifactKind { title, summary, actionItems }

class AppSettings {
  const AppSettings({required this.ollamaBaseUrl, required this.ollamaModel});

  static const legacyDefaultModel = 'gemma3:1b';
  static const defaults = AppSettings(
    ollamaBaseUrl: 'http://127.0.0.1:11434',
    ollamaModel: 'gemma4:e4b',
  );

  final String ollamaBaseUrl;
  final String ollamaModel;

  AppSettings copyWith({String? ollamaBaseUrl, String? ollamaModel}) {
    return AppSettings(
      ollamaBaseUrl: ollamaBaseUrl ?? this.ollamaBaseUrl,
      ollamaModel: ollamaModel ?? this.ollamaModel,
    );
  }
}

class ProcessorToggles {
  const ProcessorToggles({
    required this.spelling,
    required this.formatting,
    required this.clarity,
    required this.verification,
  });

  final bool spelling;
  final bool formatting;
  final bool clarity;
  final bool verification;

  ProcessorToggles copyWith({
    bool? spelling,
    bool? formatting,
    bool? clarity,
    bool? verification,
  }) {
    return ProcessorToggles(
      spelling: spelling ?? this.spelling,
      formatting: formatting ?? this.formatting,
      clarity: clarity ?? this.clarity,
      verification: verification ?? this.verification,
    );
  }
}

class NotebookVersion {
  const NotebookVersion({
    required this.id,
    required this.createdAt,
    required this.rawContent,
    required this.enhancedContent,
    required this.modelMode,
  });

  final String id;
  final DateTime createdAt;
  final String rawContent;
  final String enhancedContent;
  final ModelMode modelMode;

  NotebookVersion copyWith({
    String? id,
    DateTime? createdAt,
    String? rawContent,
    String? enhancedContent,
    ModelMode? modelMode,
  }) {
    return NotebookVersion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      rawContent: rawContent ?? this.rawContent,
      enhancedContent: enhancedContent ?? this.enhancedContent,
      modelMode: modelMode ?? this.modelMode,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'rawContent': rawContent,
      'enhancedContent': enhancedContent,
      'modelMode': modelMode.name,
    };
  }

  factory NotebookVersion.fromJson(Map<String, dynamic> json) {
    return NotebookVersion(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      rawContent: json['rawContent'] as String,
      enhancedContent: json['enhancedContent'] as String,
      modelMode: _modelModeFromName(json['modelMode'] as String?),
    );
  }
}

class NotebookNote {
  const NotebookNote({
    required this.id,
    required this.title,
    required this.category,
    required this.createdAt,
    required this.updatedAt,
    required this.rawContent,
    required this.versions,
  });

  final String id;
  final String title;
  final String category;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String rawContent;
  final List<NotebookVersion> versions;

  NotebookNote copyWith({
    String? id,
    String? title,
    String? category,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? rawContent,
    List<NotebookVersion>? versions,
  }) {
    return NotebookNote(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rawContent: rawContent ?? this.rawContent,
      versions: versions ?? this.versions,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'category': category,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'rawContent': rawContent,
      'versions': versions.map((version) => version.toJson()).toList(),
    };
  }

  factory NotebookNote.fromJson(Map<String, dynamic> json) {
    final versionsJson = json['versions'] as List<dynamic>? ?? const [];
    return NotebookNote(
      id: json['id'] as String,
      title: json['title'] as String,
      category: json['category'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      rawContent: json['rawContent'] as String? ?? '',
      versions: versionsJson
          .map(
            (version) =>
                NotebookVersion.fromJson(version as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class EnhancementChange {
  const EnhancementChange({
    required this.type,
    required this.label,
    required this.description,
  });

  final ChangeType type;
  final String label;
  final String description;
}

class VerificationFlag {
  const VerificationFlag({
    required this.status,
    required this.claimText,
    required this.note,
    required this.confidence,
  });

  final VerificationStatus status;
  final String claimText;
  final String note;
  final double confidence;
}

class EnhancementSnapshot {
  const EnhancementSnapshot({
    required this.enhancedContent,
    required this.summary,
    required this.changes,
    required this.flags,
    this.processorStatuses = const [],
  });

  final String enhancedContent;
  final String summary;
  final List<EnhancementChange> changes;
  final List<VerificationFlag> flags;
  final List<ProcessorStatus> processorStatuses;
}

class NormalizedNote {
  const NormalizedNote({
    required this.rawText,
    required this.analysisText,
    required this.revisionId,
  });

  final String rawText;
  final String analysisText;
  final String revisionId;
}

class LineNode {
  const LineNode({
    required this.index,
    required this.sourceLine,
    required this.trimmed,
    required this.kind,
    required this.indent,
    this.headingLevel,
    this.orderedIndex,
    this.checkboxChecked,
    this.key,
    this.value,
  });

  final int index;
  final String sourceLine;
  final String trimmed;
  final LineKind kind;
  final int indent;
  final int? headingLevel;
  final int? orderedIndex;
  final bool? checkboxChecked;
  final String? key;
  final String? value;

  bool get isBlank => kind == LineKind.blank;
}

class BlockNode {
  const BlockNode({
    required this.index,
    required this.kind,
    required this.lines,
  });

  final int index;
  final BlockKind kind;
  final List<LineNode> lines;

  int get startLine => lines.first.index;
  int get endLine => lines.last.index;
}

class StructureMetrics {
  const StructureMetrics({
    required this.lineCount,
    required this.nonBlankLineCount,
    required this.blockCount,
    required this.headingCount,
    required this.bulletCount,
    required this.orderedItemCount,
    required this.checkboxCount,
    required this.checkedCheckboxCount,
    required this.quoteLineCount,
    required this.codeLineCount,
    required this.keyValueCount,
    required this.tableRowCount,
  });

  final int lineCount;
  final int nonBlankLineCount;
  final int blockCount;
  final int headingCount;
  final int bulletCount;
  final int orderedItemCount;
  final int checkboxCount;
  final int checkedCheckboxCount;
  final int quoteLineCount;
  final int codeLineCount;
  final int keyValueCount;
  final int tableRowCount;
}

class NoteStructure {
  const NoteStructure({
    required this.note,
    required this.lines,
    required this.blocks,
    required this.metrics,
    required this.protectedTokens,
  });

  final NormalizedNote note;
  final List<LineNode> lines;
  final List<BlockNode> blocks;
  final StructureMetrics metrics;
  final Set<String> protectedTokens;
}

class ChampionDraft {
  const ChampionDraft({
    required this.text,
    required this.structure,
    required this.changes,
    required this.renderedLinesBySourceIndex,
  });

  final String text;
  final NoteStructure structure;
  final List<EnhancementChange> changes;
  final Map<int, String> renderedLinesBySourceIndex;
}

class AcceptanceIssue {
  const AcceptanceIssue({required this.code, required this.message});

  final String code;
  final String message;
}

class AcceptanceReport {
  const AcceptanceReport({
    required this.decision,
    required this.issues,
    this.acceptedText,
  });

  final AcceptanceDecision decision;
  final List<AcceptanceIssue> issues;
  final String? acceptedText;

  bool get accepted => decision == AcceptanceDecision.accepted;
}

class LineEditProposal {
  const LineEditProposal({
    required this.lineIndex,
    required this.replacement,
    required this.type,
    required this.label,
    required this.description,
  });

  final int lineIndex;
  final String replacement;
  final ChangeType type;
  final String label;
  final String description;
}

class ArtifactProposal {
  const ArtifactProposal({
    required this.kind,
    required this.value,
    required this.evidenceLineIndexes,
    required this.label,
    required this.description,
  });

  final ArtifactKind kind;
  final String value;
  final List<int> evidenceLineIndexes;
  final String label;
  final String description;
}

class ModelProposal {
  const ModelProposal({this.lineEdits = const [], this.artifacts = const []});

  final List<LineEditProposal> lineEdits;
  final List<ArtifactProposal> artifacts;
}

class ProposalAcceptanceResult {
  const ProposalAcceptanceResult({
    this.acceptedLineEdits = const [],
    this.acceptedArtifacts = const [],
    this.issues = const [],
  });

  final List<LineEditProposal> acceptedLineEdits;
  final List<ArtifactProposal> acceptedArtifacts;
  final List<AcceptanceIssue> issues;
}

class ProcessorStatus {
  const ProcessorStatus({
    required this.kind,
    required this.state,
    required this.label,
    required this.detail,
  });

  final ProcessorKind kind;
  final ProcessorState state;
  final String label;
  final String detail;
}

class EnhancementRequest {
  const EnhancementRequest({
    required this.rawContent,
    required this.modelMode,
    required this.toggles,
    this.revisionId,
  });

  final String rawContent;
  final ModelMode modelMode;
  final ProcessorToggles toggles;
  final int? revisionId;
}

String encodeNotes(List<NotebookNote> notes) {
  return const JsonEncoder.withIndent(
    '  ',
  ).convert({'notes': notes.map((note) => note.toJson()).toList()});
}

List<NotebookNote> decodeNotes(String source) {
  final parsed = jsonDecode(source) as Map<String, dynamic>;
  final notes = parsed['notes'] as List<dynamic>? ?? const [];
  return notes
      .map((note) => NotebookNote.fromJson(note as Map<String, dynamic>))
      .toList();
}

ModelMode _modelModeFromName(String? value) {
  return ModelMode.values.firstWhere(
    (mode) => mode.name == value,
    orElse: () => ModelMode.localFast,
  );
}
