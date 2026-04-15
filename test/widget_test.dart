import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_notebook/app.dart';
import 'package:smart_notebook/data/seed_notes.dart';
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
