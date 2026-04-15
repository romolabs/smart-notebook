import 'package:flutter/material.dart';

import 'features/workspace/notebook_workspace.dart';
import 'models/notebook_models.dart';
import 'services/mock_enhancement_engine.dart';
import 'services/notebook_repository.dart';
import 'services/ollama_local_model_adapter.dart';

class SmartNotebookApp extends StatelessWidget {
  const SmartNotebookApp({
    super.key,
    this.engine = const MockEnhancementEngine(
      localModelAdapter: OllamaLocalModelAdapter(model: 'gemma4:e4b'),
    ),
    this.repository,
    this.initialNotes,
  });

  final MockEnhancementEngine engine;
  final NotebookRepository? repository;
  final List<NotebookNote>? initialNotes;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF167C80),
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'Smart Notebook',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF4F1EA),
        textTheme: Typography.blackCupertino,
      ),
      home: NotebookWorkspace(
        engine: engine,
        repository: repository ?? NotebookRepository.local(engine: engine),
        initialNotes: initialNotes,
      ),
    );
  }
}
