import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_notebook/app.dart';
import 'package:smart_notebook/data/seed_notes.dart';
import 'package:smart_notebook/services/mock_enhancement_engine.dart';
import 'package:smart_notebook/services/notebook_repository.dart';

void main() {
  testWidgets('renders split notebook workspace', (tester) async {
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
        engine: const MockEnhancementEngine(),
        repository: NotebookRepository.forTesting(
          databasePath: file.path,
          engine: const MockEnhancementEngine(),
        ),
        initialNotes: buildSeedNotes(const MockEnhancementEngine()),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Notebook'), findsOneWidget);
    expect(find.text('Raw'), findsOneWidget);
    expect(find.text('Enhanced'), findsOneWidget);
    expect(find.text('Local Fast'), findsOneWidget);
    expect(find.text('Cloud Accurate'), findsOneWidget);
  });
}
