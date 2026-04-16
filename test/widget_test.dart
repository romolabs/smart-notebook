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
      processorStatuses: const [],
    );
  }
}
