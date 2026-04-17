import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_notebook/app.dart';
import 'package:smart_notebook/data/seed_notes.dart';
import 'package:smart_notebook/features/workspace/notebook_workspace.dart';
import 'package:smart_notebook/models/notebook_models.dart';
import 'package:smart_notebook/services/ai_command_service.dart';
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

  testWidgets('compact workspace avoids bottom overflow in a short window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpApp(tester);
    await tester.pumpAndSettle();

    expect(find.text('Raw'), findsOneWidget);
    expect(find.text('Enhanced'), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  testWidgets('raw editor expands structural commands deterministically', (
    tester,
  ) async {
    await _pumpApp(tester);

    final editor = find.byType(TextField).at(1);
    await tester.enterText(editor, '/h1 ');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    var textField = tester.widget<TextField>(editor);
    expect(textField.controller?.text, '# ');

    await tester.enterText(editor, '/math ');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    textField = tester.widget<TextField>(editor);
    expect(textField.controller?.text, '/math\n\n/end');
    expect(textField.controller?.selection.baseOffset, '/math\n'.length);
  });

  testWidgets('writer toolbar inserts a math block scaffold', (tester) async {
    await _pumpApp(tester);

    final editor = find.byType(TextField).at(1);
    await tester.enterText(editor, '');
    await tester.pump();
    await tester.tap(find.text('Math'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final textField = tester.widget<TextField>(editor);
    expect(textField.controller?.text, '/math\n\n/end');
    expect(textField.controller?.selection.baseOffset, '/math\n'.length);
  });

  testWidgets('raw editor expands /table into a table scaffold', (
    tester,
  ) async {
    await _pumpApp(tester);

    final editor = find.byType(TextField).at(1);
    await tester.enterText(editor, '/table ');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final textField = tester.widget<TextField>(editor);
    expect(
      textField.controller?.text,
      '/table\n| Column 1 | Column 2 |\n| --- | --- |\n| Value | Value |\n/end',
    );
    expect(textField.controller?.selection.baseOffset, '/table\n| '.length);
  });

  testWidgets('enhanced pane renders /table blocks as table widgets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final file = File(
      '${Directory.systemTemp.path}/smart_notebook_widget_table_block_test.db',
    );
    if (file.existsSync()) {
      file.deleteSync();
    }
    addTearDown(() {
      if (file.existsSync()) {
        file.deleteSync();
      }
    });

    final now = DateTime.now();
    final note = NotebookNote(
      id: 'table-note',
      title: 'Table note',
      category: 'Study',
      createdAt: now,
      updatedAt: now,
      rawContent: r'''
/table
| Name | Score |
| --- | --- |
| Alice | 10 |
/end

- check assumptions
''',
      versions: const [],
    );

    final repository = NotebookRepository.forTesting(
      databasePath: file.path,
      engine: const MockEnhancementEngine(),
    );
    addTearDown(repository.close);

    await tester.pumpWidget(
      MaterialApp(
        home: NotebookWorkspace(
          engine: const MockEnhancementEngine(),
          repository: repository,
          settings: AppSettings.defaults,
          onSaveSettings: (_) async {},
          initialNotes: [note],
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(Table), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Score'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.textContaining('check assumptions'), findsWidgets);
  });

  testWidgets('enhanced pane renders /math blocks as math widgets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final file = File(
      '${Directory.systemTemp.path}/smart_notebook_widget_math_block_test.db',
    );
    if (file.existsSync()) {
      file.deleteSync();
    }
    addTearDown(() {
      if (file.existsSync()) {
        file.deleteSync();
      }
    });

    final now = DateTime.now();
    final note = NotebookNote(
      id: 'math-note',
      title: 'Math note',
      category: 'Study',
      createdAt: now,
      updatedAt: now,
      rawContent: r'''
proof notes
/math
\begin{align}
E[X] &= \sum_i x_i p_i \\
Var(X) &= E[X^2] - (E[X])^2
\end{align}
/end

- check assumptions
''',
      versions: const [],
    );

    final repository = NotebookRepository.forTesting(
      databasePath: file.path,
      engine: const MockEnhancementEngine(),
    );
    addTearDown(repository.close);

    await tester.pumpWidget(
      MaterialApp(
        home: NotebookWorkspace(
          engine: const MockEnhancementEngine(),
          repository: repository,
          settings: AppSettings.defaults,
          onSaveSettings: (_) async {},
          initialNotes: [note],
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(Math), findsWidgets);
    expect(find.text('/math'), findsNothing);
    expect(find.text('/end'), findsNothing);
    expect(find.textContaining('check assumptions'), findsOneWidget);
  });

  testWidgets(
    'renders explicit // AI requests as sidecar results and opens the AI drawer',
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
        localModelAdapter: _AiCommandLocalModelAdapter(),
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
          '/math',
          r'F = ma',
          '/end',
          '//explain formula',
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
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('AI Requests'), findsOneWidget);
      expect(find.text('//explain formula'), findsOneWidget);
      expect(find.textContaining('The formula states'), findsOneWidget);

      await tester.tap(find.text('Open AI Drawer'));
      await tester.pumpAndSettle();

      expect(find.text('Formula Explanation'), findsOneWidget);
      expect(
        find.textContaining('force equals mass times acceleration'),
        findsWidgets,
      );
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

class _AiCommandLocalModelAdapter extends LocalModelAdapter {
  const _AiCommandLocalModelAdapter();

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

  @override
  Future<AiCommandResult> runAiCommand({
    required EnhancementRequest request,
    required AiCommandRequest command,
  }) async {
    return AiCommandResult(
      request: command,
      status: AiCommandStatus.completed,
      title: 'Formula Explanation',
      content:
          'The formula states that force equals mass times acceleration, so stronger acceleration or more mass implies more force.',
      detail: 'Test AI response completed.',
      providerLabel: 'Test local AI',
    );
  }
}
