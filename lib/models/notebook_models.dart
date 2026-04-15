import 'dart:convert';

enum ModelMode { localFast, cloudAccurate }

enum ChangeType { spelling, formatting, clarity, verification }

enum VerificationStatus { warning, needsReview }

enum ProcessorKind { formatter, verifier }

enum ProcessorState { completed, skipped, unavailable, failed }

class AppSettings {
  const AppSettings({required this.ollamaBaseUrl, required this.ollamaModel});

  static const legacyDefaultModel = 'gemma4:e4b';
  static const defaults = AppSettings(
    ollamaBaseUrl: 'http://127.0.0.1:11434',
    ollamaModel: 'gemma3:1b',
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
  });

  final String rawContent;
  final ModelMode modelMode;
  final ProcessorToggles toggles;
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
