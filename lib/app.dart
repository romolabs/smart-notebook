import 'package:flutter/material.dart';

import 'features/workspace/notebook_workspace.dart';
import 'models/notebook_models.dart';
import 'services/mock_enhancement_engine.dart';
import 'services/notebook_repository.dart';
import 'services/ollama_local_model_adapter.dart';

class SmartNotebookApp extends StatefulWidget {
  const SmartNotebookApp({
    super.key,
    this.repository,
    this.initialNotes,
    this.initialSettings,
  });

  final NotebookRepository? repository;
  final List<NotebookNote>? initialNotes;
  final AppSettings? initialSettings;

  @override
  State<SmartNotebookApp> createState() => _SmartNotebookAppState();
}

class _SmartNotebookAppState extends State<SmartNotebookApp> {
  late final NotebookRepository _repository;
  AppSettings? _settings;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ??
        NotebookRepository.local(
          engine: _buildEngine(widget.initialSettings ?? AppSettings.defaults),
        );
    if (widget.initialSettings case final settings?) {
      _settings = settings;
    } else {
      _loadSettings();
    }
  }

  @override
  void dispose() {
    _repository.close();
    super.dispose();
  }

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
      home: _settings == null
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : NotebookWorkspace(
              engine: _buildEngine(_settings!),
              repository: _repository,
              initialNotes: widget.initialNotes,
              settings: _settings!,
              onSaveSettings: _saveSettings,
            ),
    );
  }

  Future<void> _loadSettings() async {
    final settings = await _repository.loadSettings();
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = settings;
    });
  }

  Future<void> _saveSettings(AppSettings settings) async {
    await _repository.saveSettings(settings);
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = settings;
    });
  }

  MockEnhancementEngine _buildEngine(AppSettings settings) {
    return MockEnhancementEngine(
      localModelAdapter: OllamaLocalModelAdapter(
        baseUrl: settings.ollamaBaseUrl,
        model: settings.ollamaModel,
      ),
    );
  }
}
