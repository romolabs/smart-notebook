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
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Raw'), findsOneWidget);
    expect(find.text('Enhanced'), findsOneWidget);
    expect(find.text('Local Fast'), findsOneWidget);
    expect(find.text('Cloud Accurate'), findsOneWidget);
    expect(find.text('Writer tools'), findsOneWidget);
    expect(find.text('Heading'), findsOneWidget);
  });

  testWidgets('filters notes by search and workspace', (tester) async {
    await _pumpApp(tester);

    final schoolChip = find.widgetWithText(FilterChip, 'School');
    await tester.ensureVisible(schoolChip);
    await tester.tap(schoolChip);
    await tester.pumpAndSettle();

    expect(find.text('Lecture scraps'), findsWidgets);
    expect(find.text('Meeting notes with designer'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'lecture');
    await tester.pumpAndSettle();

    expect(find.text('Lecture scraps'), findsWidgets);
    expect(find.text('Meeting notes with designer'), findsNothing);

    await tester.tap(find.text('Lecture scraps').first);
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
    final mathButton = find.text('Math');
    await tester.ensureVisible(mathButton);
    await tester.tap(mathButton);
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
      workspace: 'School',
      notebook: 'Tables',
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
      workspace: 'School',
      notebook: 'Math',
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
        workspace: 'Product',
        notebook: 'AI Commands',
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

  testWidgets('appends explicit AI results back into the raw note on demand', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final file = File(
      '${Directory.systemTemp.path}/smart_notebook_widget_ai_apply_test.db',
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
      id: 'apply-ai-note',
      title: 'Apply AI note',
      workspace: 'School',
      notebook: 'Physics',
      category: 'Study',
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

    await tester.tap(find.text('Append below'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    final editor = tester.widget<TextField>(find.byType(TextField).at(1));
    expect(editor.controller?.text.contains('Formula Explanation'), isTrue);
    expect(
      editor.controller?.text.contains('force equals mass times acceleration'),
      isTrue,
    );
  });

  testWidgets(
    'Cloud Accurate routes explicit AI requests through the cloud adapter',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final file = File(
        '${Directory.systemTemp.path}/smart_notebook_widget_cloud_command_test.db',
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
        cloudCommandAdapter: _AiCommandCloudModelAdapter(),
      );
      final repository = NotebookRepository.forTesting(
        databasePath: file.path,
        engine: engine,
      );
      addTearDown(repository.close);

      final now = DateTime.now();
      final note = NotebookNote(
        id: 'cloud-command-note',
        title: 'Cloud command note',
        workspace: 'Product',
        notebook: 'Definitions',
        category: 'General',
        createdAt: now,
        updatedAt: now,
        rawContent: [
          'Entropy note',
          'Entropy measures uncertainty in a system.',
          '//define entropy',
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

      await tester.tap(find.text('Cloud Accurate'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('AI Requests'), findsOneWidget);
      expect(find.text('//define entropy'), findsOneWidget);
      expect(find.textContaining('Cloud definition'), findsOneWidget);
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
      workspace: 'Personal',
      notebook: 'Inbox',
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

  testWidgets('creates a new note inside the active notebook scope', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final file = File(
      '${Directory.systemTemp.path}/smart_notebook_widget_scope_creation_test.db',
    );
    if (file.existsSync()) {
      file.deleteSync();
    }
    addTearDown(() {
      if (file.existsSync()) {
        file.deleteSync();
      }
    });

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
          initialNotes: buildSeedNotes(const MockEnhancementEngine()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final schoolChip = find.widgetWithText(FilterChip, 'School');
    await tester.ensureVisible(schoolChip);
    await tester.tap(schoolChip);
    await tester.pumpAndSettle();
    final notebookChip = find.widgetWithText(FilterChip, 'General Study');
    await tester.ensureVisible(notebookChip);
    await tester.tap(notebookChip);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'New'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.textContaining('Untitled note'), findsWidgets);
    expect(find.text('General Study'), findsWidgets);
  });

  test(
    'repository creates and deletes empty workspace/notebook scopes',
    () async {
      final file = File(
        '${Directory.systemTemp.path}/smart_notebook_scope_repository_test.db',
      );
      if (file.existsSync()) {
        file.deleteSync();
      }
      addTearDown(() {
        if (file.existsSync()) {
          file.deleteSync();
        }
      });

      final repository = NotebookRepository.forTesting(
        databasePath: file.path,
        engine: const MockEnhancementEngine(),
      );
      addTearDown(repository.close);

      await repository.createWorkspace('Research');
      await repository.createNotebook(workspace: 'Research', notebook: 'Ideas');

      final workspaces = await repository.loadWorkspaces();
      final notebooks = await repository.loadNotebooks();
      expect(
        workspaces.map((workspace) => workspace.name),
        contains('Research'),
      );
      expect(
        notebooks.any(
          (notebook) =>
              notebook.workspace == 'Research' && notebook.name == 'Ideas',
        ),
        isTrue,
      );

      await repository.deleteNotebook(workspace: 'Research', notebook: 'Ideas');
      await repository.deleteWorkspace('Research');

      final remainingWorkspaces = await repository.loadWorkspaces();
      final remainingNotebooks = await repository.loadNotebooks();
      expect(
        remainingWorkspaces.map((workspace) => workspace.name),
        isNot(contains('Research')),
      );
      expect(
        remainingNotebooks.any(
          (notebook) =>
              notebook.workspace == 'Research' && notebook.name == 'Ideas',
        ),
        isFalse,
      );
    },
  );

  test(
    'repository renames notebook and workspace scopes alongside notes',
    () async {
      final file = File(
        '${Directory.systemTemp.path}/smart_notebook_scope_rename_test.db',
      );
      if (file.existsSync()) {
        file.deleteSync();
      }
      addTearDown(() {
        if (file.existsSync()) {
          file.deleteSync();
        }
      });

      final repository = NotebookRepository.forTesting(
        databasePath: file.path,
        engine: const MockEnhancementEngine(),
      );
      addTearDown(repository.close);

      final now = DateTime.now();
      await repository.saveNotes([
        NotebookNote(
          id: 'scope-note',
          title: 'Scope note',
          workspace: 'School',
          notebook: 'General Study',
          category: 'Study',
          createdAt: now,
          updatedAt: now,
          rawContent: 'entropy notes',
          versions: const [],
        ),
      ]);

      await repository.renameNotebook(
        workspace: 'School',
        currentName: 'General Study',
        nextName: 'Entropy Lab',
      );
      await repository.renameWorkspace(
        currentName: 'School',
        nextName: 'Courses',
      );

      final notes = await repository.loadNotes();
      final workspaces = await repository.loadWorkspaces();
      final notebooks = await repository.loadNotebooks();

      expect(notes.single.workspace, 'Courses');
      expect(notes.single.notebook, 'Entropy Lab');
      expect(
        workspaces.map((workspace) => workspace.name),
        contains('Courses'),
      );
      expect(
        notebooks.any(
          (notebook) =>
              notebook.workspace == 'Courses' && notebook.name == 'Entropy Lab',
        ),
        isTrue,
      );
    },
  );

  testWidgets('renames selected note and updates rail plus top bar', (
    tester,
  ) async {
    await _pumpApp(tester);

    final schoolChip = find.widgetWithText(FilterChip, 'School');
    await tester.ensureVisible(schoolChip);
    await tester.tap(schoolChip);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lecture scraps').first);
    await tester.pumpAndSettle();

    final editorBefore = tester.widget<TextField>(find.byType(TextField).at(1));
    expect(
      editorBefore.controller?.text.contains('teh network has 1200 samples'),
      isTrue,
    );

    await tester.tap(
      find.byKey(const ValueKey('selected-note-actions-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename note'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('rename-note-field')),
      'Entropy review',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Entropy review'), findsWidgets);
    expect(find.text('Lecture scraps'), findsNothing);

    final editorAfter = tester.widget<TextField>(find.byType(TextField).at(1));
    expect(
      editorAfter.controller?.text.contains('teh network has 1200 samples'),
      isTrue,
    );
  });

  testWidgets('moves selected note to another notebook and keeps it selected', (
    tester,
  ) async {
    await _pumpApp(tester);

    final schoolChip = find.widgetWithText(FilterChip, 'School');
    await tester.ensureVisible(schoolChip);
    await tester.tap(schoolChip);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lecture scraps').first);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('selected-note-actions-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move note'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('move-note-workspace-field')),
      'School',
    );
    await tester.enterText(
      find.byKey(const ValueKey('move-note-notebook-field')),
      'Exam Prep',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Move'));
    await tester.pumpAndSettle();

    expect(find.text('Exam Prep'), findsWidgets);
    expect(find.text('Lecture scraps'), findsWidgets);
  });

  testWidgets('deletes selected note and falls back to another note', (
    tester,
  ) async {
    await _pumpApp(tester);

    final schoolChip = find.widgetWithText(FilterChip, 'School');
    await tester.ensureVisible(schoolChip);
    await tester.tap(schoolChip);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lecture scraps').first);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('selected-note-actions-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete note'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Lecture scraps'), findsNothing);
    expect(find.text('AI notebook product direction'), findsWidgets);
    expect(find.text('No notes available yet.'), findsNothing);
  });

  testWidgets('restores a saved raw snapshot into the editor', (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final file = File(
      '${Directory.systemTemp.path}/smart_notebook_widget_restore_raw_test.db',
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
      id: 'history-note',
      title: 'History note',
      workspace: 'School',
      notebook: 'Physics',
      category: 'Study',
      createdAt: now,
      updatedAt: now,
      rawContent: 'Current draft',
      versions: [
        NotebookVersion(
          id: 'history-old',
          createdAt: now.subtract(const Duration(hours: 2)),
          rawContent: 'Original lecture draft',
          enhancedContent: 'Enhanced lecture draft',
          modelMode: ModelMode.localFast,
        ),
      ],
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
    await tester.pumpAndSettle();

    final restoreButton = find.byKey(const ValueKey('restore-raw-history-old'));
    await tester.ensureVisible(restoreButton);
    await tester.tap(restoreButton);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    final editor = tester.widget<TextField>(find.byType(TextField).at(1));
    expect(editor.controller?.text, 'Original lecture draft');
  });

  testWidgets('appends a saved enhanced snapshot into the editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final file = File(
      '${Directory.systemTemp.path}/smart_notebook_widget_apply_enhanced_test.db',
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
      id: 'history-note-enhanced',
      title: 'History note enhanced',
      workspace: 'School',
      notebook: 'Physics',
      category: 'Study',
      createdAt: now,
      updatedAt: now,
      rawContent: 'Current scratchpad',
      versions: [
        NotebookVersion(
          id: 'history-enhanced',
          createdAt: now.subtract(const Duration(hours: 2)),
          rawContent: 'Old raw scratchpad',
          enhancedContent: 'Polished explanation with structure',
          modelMode: ModelMode.cloudAccurate,
        ),
      ],
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
    await tester.pumpAndSettle();

    final applyButton = find.byKey(
      const ValueKey('append-enhanced-history-enhanced'),
    );
    await tester.ensureVisible(applyButton);
    await tester.tap(applyButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    final editor = tester.widget<TextField>(find.byType(TextField).at(1));
    expect(editor.controller?.text, contains('Current scratchpad'));
    expect(
      editor.controller?.text,
      contains('Polished explanation with structure'),
    );
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

class _AiCommandCloudModelAdapter extends CloudCommandAdapter {
  const _AiCommandCloudModelAdapter();

  @override
  Future<AiCommandResult> runAiCommand({
    required EnhancementRequest request,
    required AiCommandRequest command,
  }) async {
    return AiCommandResult(
      request: command,
      status: AiCommandStatus.completed,
      title: 'Definition',
      content:
          'Cloud definition: entropy is a measure of uncertainty or disorder in the system being described.',
      detail: 'Test cloud AI response completed.',
      providerLabel: 'OpenAI gpt-5.4-mini',
    );
  }
}
