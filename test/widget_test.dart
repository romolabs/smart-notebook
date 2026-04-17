import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_notebook/app.dart';
import 'package:smart_notebook/data/seed_notes.dart';
import 'package:smart_notebook/features/workspace/notebook_workspace.dart';
import 'package:smart_notebook/models/notebook_models.dart';
import 'package:smart_notebook/services/mock_enhancement_engine.dart';
import 'package:smart_notebook/services/notebook_repository.dart';

void main() {
  testWidgets('renders split notebook workspace', (tester) async {
    await _pumpApp(tester);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Notebook'), findsOneWidget);
    expect(find.text('Raw'), findsOneWidget);
    expect(find.text('Enhanced'), findsOneWidget);
    expect(find.text('Local Fast'), findsOneWidget);
    expect(find.text('Cloud Accurate'), findsOneWidget);
    expect(find.text('Writer tools'), findsOneWidget);
    expect(find.text('Heading'), findsOneWidget);
  });

  testWidgets('filters notes and keeps tapped note selected', (tester) async {
    await _pumpApp(tester);

    await tester.enterText(find.byType(TextField).first, 'lecture');
    await tester.pumpAndSettle();

    expect(find.text('Lecture scraps'), findsOneWidget);
    expect(find.text('Meeting notes with designer'), findsNothing);

    await tester.tap(find.text('Lecture scraps'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Lecture scraps'), findsNWidgets(2));
  });

  testWidgets('raw editor expands inline symbol shortcuts deterministically', (
    tester,
  ) async {
    await _pumpApp(tester);

    final editor = find.byType(TextField).at(1);
    await tester.enterText(editor, '/sigma ');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final textField = tester.widget<TextField>(editor);
    expect(textField.controller?.text, 'σ ');
    expect(find.textContaining('σ'), findsWidgets);
  });

  testWidgets(
    'renders trust-first merged output and keeps model artifacts out of visible panes',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final file = File(
        '${Directory.systemTemp.path}/smart_notebook_widget_trust_first_test.db',
      );
      if (file.existsSync()) {
        file.deleteSync();
      }
      addTearDown(() {
        if (file.existsSync()) {
          file.deleteSync();
        }
      });

      const engine = MockEnhancementEngine(
        localModelAdapter: _TrustFirstLocalModelAdapter(),
      );
      final repository = NotebookRepository.forTesting(
        databasePath: file.path,
        engine: engine,
      );
      addTearDown(repository.close);

      final now = DateTime.now();
      final note = NotebookNote(
        id: 'trust-first-note',
        title: 'Trust-first note',
        category: 'General',
        createdAt: now,
        updatedAt: now,
        rawContent: [
          'Project sync',
          '- call alice at 3',
          '- budget 1200',
        ].join('\n'),
        versions: const [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NotebookWorkspace(
            engine: engine,
            repository: repository,
            settings: AppSettings.defaults,
            onSaveSettings: (_) async {},
            initialNotes: [note],
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Formatter: Active'), findsOneWidget);
      expect(find.text('Verifier: Active'), findsOneWidget);
      expect(find.text('Capitalize attendee'), findsOneWidget);
      expect(find.text('Review hints'), findsOneWidget);
      expect(find.text('Numeric claim detected'), findsOneWidget);
      expect(find.text('Summary'), findsOneWidget);
      expect(find.textContaining('call Alice at 3 pm'), findsOneWidget);
      expect(find.text('Model-only summary should stay sidecar'), findsNothing);
      expect(find.text('Model-only action list'), findsNothing);
    },
  );

  testWidgets('ignores stale enhancement responses and keeps latest snapshot', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final file = File(
      '${Directory.systemTemp.path}/smart_notebook_widget_stale_test.db',
    );
    if (file.existsSync()) {
      file.deleteSync();
    }
    addTearDown(() {
      if (file.existsSync()) {
        file.deleteSync();
      }
    });

    final engine = _DelayedEngine();
    final repository = NotebookRepository.forTesting(
      databasePath: file.path,
      engine: engine,
    );
    addTearDown(repository.close);

    final now = DateTime.now();
    final note = NotebookNote(
      id: 'race-note',
      title: 'Race note',
      category: 'General',
      createdAt: now,
      updatedAt: now,
      rawContent: 'seed',
      versions: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NotebookWorkspace(
          engine: engine,
          repository: repository,
          settings: AppSettings.defaults,
          onSaveSettings: (_) async {},
          initialNotes: [note],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    final editor = find.byType(TextField).at(1);
    await tester.enterText(editor, 'first note');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(editor, 'second note');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.textContaining('Enhanced: second note'), findsOneWidget);
    expect(find.textContaining('Enhanced: first note'), findsNothing);
  });
}

Future<void> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final file = File(
    '${Directory.systemTemp.path}/smart_notebook_widget_test.json',
  );
  if (file.existsSync()) {
    file.deleteSync();
  }
  addTearDown(() {
    if (file.existsSync()) {
      file.deleteSync();
    }
  });

  await tester.pumpWidget(
    SmartNotebookApp(
      repository: NotebookRepository.forTesting(
        databasePath: file.path,
        engine: const MockEnhancementEngine(),
      ),
      initialNotes: buildSeedNotes(const MockEnhancementEngine()),
      initialSettings: AppSettings.defaults,
    ),
  );
  await tester.pump();
  for (var i = 0; i < 50; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
}

class _DelayedEngine extends MockEnhancementEngine {
  @override
  Future<EnhancementSnapshot> process(EnhancementRequest request) async {
    final delay = switch (request.rawContent) {
      'first note' => const Duration(milliseconds: 700),
      'second note' => const Duration(milliseconds: 50),
      _ => const Duration(milliseconds: 10),
    };
    await Future<void>.delayed(delay);
    return EnhancementSnapshot(
      enhancedContent: 'Enhanced: ${request.rawContent}',
      summary: 'Summary: ${request.rawContent}',
      changes: const [],
      flags: const [],
      routePlan: const RoutePlan(
        execution: RouteExecution.local,
        riskLevel: NoteRiskLevel.low,
        summary: 'Test route plan for delayed engine.',
        allowedCapabilities: [RouteCapability.lineEdits],
        editableLineIndexes: [0],
      ),
      processorStatuses: const [
        ProcessorStatus(
          kind: ProcessorKind.formatter,
          state: ProcessorState.completed,
          label: 'Formatter',
          detail: 'Test formatter completed.',
        ),
        ProcessorStatus(
          kind: ProcessorKind.verifier,
          state: ProcessorState.skipped,
          label: 'Verifier',
          detail: 'Verification skipped for test.',
        ),
      ],
    );
  }

  @override
  EnhancementSnapshot processSync(EnhancementRequest request) {
    return EnhancementSnapshot(
      enhancedContent: 'Enhanced: ${request.rawContent}',
      summary: 'Summary: ${request.rawContent}',
      changes: const [],
      flags: const [],
      routePlan: const RoutePlan(
        execution: RouteExecution.local,
        riskLevel: NoteRiskLevel.low,
        summary: 'Test route plan for delayed engine.',
        allowedCapabilities: [RouteCapability.lineEdits],
        editableLineIndexes: [0],
      ),
      processorStatuses: const [],
    );
  }
}

class _TrustFirstLocalModelAdapter extends LocalModelAdapter {
  const _TrustFirstLocalModelAdapter();

  @override
  Future<FormatterProcessorResult> runFormatter({
    required EnhancementRequest request,
    required ChampionDraft champion,
    required RoutePlan routePlan,
  }) async {
    return const FormatterProcessorResult(
      proposal: ModelProposal(
        lineEdits: [
          LineEditProposal(
            lineIndex: 1,
            replacement: '- call Alice at 3 pm',
            type: ChangeType.clarity,
            label: 'Capitalize attendee',
            description:
                'Adds a small trust-gated polish to the existing follow-up bullet.',
          ),
        ],
        artifacts: [
          ArtifactProposal(
            kind: ArtifactKind.summary,
            value: 'Model-only summary should stay sidecar',
            evidenceLineIndexes: [0, 1],
            label: 'Summary artifact',
            description: 'This should not replace the engine-authored summary.',
          ),
          ArtifactProposal(
            kind: ArtifactKind.actionItems,
            value: 'Model-only action list',
            evidenceLineIndexes: [1],
            label: 'Action artifact',
            description: 'This should not be rendered in the enhanced body.',
          ),
        ],
      ),
      status: ProcessorStatus(
        kind: ProcessorKind.formatter,
        state: ProcessorState.completed,
        label: 'Formatter',
        detail: 'Returned a bounded trust-first proposal for testing.',
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
        detail: 'Unused in this widget test adapter.',
      ),
    );
  }
}
