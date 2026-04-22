import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/seed_notes.dart';
import '../models/notebook_models.dart';
import 'mock_enhancement_engine.dart';

const _defaultWorkspaceName = 'Personal';
const _defaultNotebookName = 'Inbox';

class NotebookRepository {
  NotebookRepository._({
    required this.databaseFactory,
    required this.databasePath,
    required this.engine,
  });

  final DatabaseFactory databaseFactory;
  final String databasePath;
  final MockEnhancementEngine engine;

  Database? _database;

  factory NotebookRepository.local({
    MockEnhancementEngine engine = const MockEnhancementEngine(),
  }) {
    sqfliteFfiInit();
    final root = Directory('${Directory.current.path}/.smart_notebook');
    final path = p.join(root.path, 'smart_notebook.db');
    return NotebookRepository._(
      databaseFactory: databaseFactoryFfi,
      databasePath: path,
      engine: engine,
    );
  }

  factory NotebookRepository.forTesting({
    required String databasePath,
    MockEnhancementEngine engine = const MockEnhancementEngine(),
  }) {
    sqfliteFfiInit();
    return NotebookRepository._(
      databaseFactory: databaseFactoryFfi,
      databasePath: databasePath,
      engine: engine,
    );
  }

  Future<List<NotebookNote>> loadNotes() async {
    final db = await _openDatabase();
    final notes = await _fetchNotes(db);
    if (notes.isNotEmpty) {
      return notes;
    }

    final seeds = buildSeedNotes(engine);
    await saveNotes(seeds);
    return seeds;
  }

  Future<AppSettings> loadSettings() async {
    final db = await _openDatabase();
    final rows = await db.query(
      'app_settings',
      where: 'id = ?',
      whereArgs: ['default'],
      limit: 1,
    );
    if (rows.isEmpty) {
      await saveSettings(AppSettings.defaults);
      return AppSettings.defaults;
    }

    final row = rows.first;
    final settings = AppSettings(
      ollamaBaseUrl:
          row['ollama_base_url'] as String? ??
          AppSettings.defaults.ollamaBaseUrl,
      ollamaModel:
          row['ollama_model'] as String? ?? AppSettings.defaults.ollamaModel,
      openAiBaseUrl:
          row['openai_base_url'] as String? ??
          AppSettings.defaults.openAiBaseUrl,
      openAiApiKey:
          row['openai_api_key'] as String? ?? AppSettings.defaults.openAiApiKey,
      openAiPrimaryModel:
          row['openai_primary_model'] as String? ??
          AppSettings.defaults.openAiPrimaryModel,
      openAiFastModel:
          row['openai_fast_model'] as String? ??
          AppSettings.defaults.openAiFastModel,
    );
    if (settings.ollamaModel == AppSettings.legacyDefaultModel) {
      final migrated = settings.copyWith(
        ollamaModel: AppSettings.defaults.ollamaModel,
      );
      await saveSettings(migrated);
      return migrated;
    }
    return settings;
  }

  Future<void> saveSettings(AppSettings settings) async {
    final db = await _openDatabase();
    await db.insert('app_settings', {
      'id': 'default',
      'ollama_base_url': settings.ollamaBaseUrl,
      'ollama_model': settings.ollamaModel,
      'openai_base_url': settings.openAiBaseUrl,
      'openai_api_key': settings.openAiApiKey,
      'openai_primary_model': settings.openAiPrimaryModel,
      'openai_fast_model': settings.openAiFastModel,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveNotes(List<NotebookNote> notes) async {
    final db = await _openDatabase();

    await db.transaction((txn) async {
      await txn.delete('note_versions');
      await txn.delete('notes');

      for (final note in notes) {
        await txn.insert('notes', {
          'id': note.id,
          'title': note.title,
          'workspace': note.workspace,
          'notebook': note.notebook,
          'category': note.category,
          'created_at': note.createdAt.toIso8601String(),
          'updated_at': note.updatedAt.toIso8601String(),
          'raw_content': note.rawContent,
        });

        for (var index = 0; index < note.versions.length; index++) {
          final version = note.versions[index];
          await txn.insert('note_versions', {
            'id': version.id,
            'note_id': note.id,
            'version_number': index + 1,
            'raw_content': version.rawContent,
            'enhanced_content': version.enhancedContent,
            'model_mode': version.modelMode.name,
            'created_at': version.createdAt.toIso8601String(),
          });
        }
      }
    });
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Future<Database> _openDatabase() async {
    if (_database case final db?) {
      return db;
    }

    await Directory(p.dirname(databasePath)).create(recursive: true);
    _database = await databaseFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 4,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON;');
        },
        onCreate: (db, version) async {
          await _createSchema(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _createSettingsTable(db);
          }
          if (oldVersion < 3) {
            await db.execute(
              'ALTER TABLE app_settings ADD COLUMN openai_base_url TEXT NOT NULL DEFAULT \'${AppSettings.defaults.openAiBaseUrl}\';',
            );
            await db.execute(
              'ALTER TABLE app_settings ADD COLUMN openai_api_key TEXT NOT NULL DEFAULT \'\';',
            );
            await db.execute(
              'ALTER TABLE app_settings ADD COLUMN openai_primary_model TEXT NOT NULL DEFAULT \'${AppSettings.defaults.openAiPrimaryModel}\';',
            );
            await db.execute(
              'ALTER TABLE app_settings ADD COLUMN openai_fast_model TEXT NOT NULL DEFAULT \'${AppSettings.defaults.openAiFastModel}\';',
            );
          }
          if (oldVersion < 4) {
            await db.execute(
              'ALTER TABLE notes ADD COLUMN workspace TEXT NOT NULL DEFAULT \'$_defaultWorkspaceName\';',
            );
            await db.execute(
              'ALTER TABLE notes ADD COLUMN notebook TEXT NOT NULL DEFAULT \'$_defaultNotebookName\';',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_notes_workspace_notebook ON notes(workspace, notebook, updated_at DESC);',
            );
          }
        },
      ),
    );
    return _database!;
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE schema_migrations (
        version INTEGER PRIMARY KEY,
        applied_at TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        workspace TEXT NOT NULL,
        notebook TEXT NOT NULL,
        category TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        raw_content TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE note_versions (
        id TEXT PRIMARY KEY,
        note_id TEXT NOT NULL,
        version_number INTEGER NOT NULL,
        raw_content TEXT NOT NULL,
        enhanced_content TEXT NOT NULL,
        model_mode TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(note_id) REFERENCES notes(id) ON DELETE CASCADE,
        UNIQUE(note_id, version_number)
      );
    ''');

    await db.execute(
      'CREATE INDEX idx_notes_updated_at ON notes(updated_at DESC);',
    );
    await db.execute(
      'CREATE INDEX idx_notes_workspace_notebook ON notes(workspace, notebook, updated_at DESC);',
    );
    await db.execute(
      'CREATE INDEX idx_note_versions_note_id ON note_versions(note_id, version_number DESC);',
    );
    await _createSettingsTable(db);
    await db.insert('schema_migrations', {
      'version': 4,
      'applied_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _createSettingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        id TEXT PRIMARY KEY,
        ollama_base_url TEXT NOT NULL,
        ollama_model TEXT NOT NULL,
        openai_base_url TEXT NOT NULL,
        openai_api_key TEXT NOT NULL,
        openai_primary_model TEXT NOT NULL,
        openai_fast_model TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    await db.insert('app_settings', {
      'id': 'default',
      'ollama_base_url': AppSettings.defaults.ollamaBaseUrl,
      'ollama_model': AppSettings.defaults.ollamaModel,
      'openai_base_url': AppSettings.defaults.openAiBaseUrl,
      'openai_api_key': AppSettings.defaults.openAiApiKey,
      'openai_primary_model': AppSettings.defaults.openAiPrimaryModel,
      'openai_fast_model': AppSettings.defaults.openAiFastModel,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<NotebookNote>> _fetchNotes(Database db) async {
    final notesRows = await db.query('notes', orderBy: 'updated_at DESC');
    if (notesRows.isEmpty) {
      return const [];
    }

    final versionRows = await db.query(
      'note_versions',
      orderBy: 'note_id ASC, version_number ASC',
    );

    final versionsByNoteId = <String, List<NotebookVersion>>{};
    for (final row in versionRows) {
      final noteId = row['note_id'] as String;
      versionsByNoteId
          .putIfAbsent(noteId, () => [])
          .add(
            NotebookVersion(
              id: row['id'] as String,
              createdAt: DateTime.parse(row['created_at'] as String),
              rawContent: row['raw_content'] as String,
              enhancedContent: row['enhanced_content'] as String,
              modelMode: _modelModeFromName(row['model_mode'] as String?),
            ),
          );
    }

    return notesRows
        .map((row) {
          final id = row['id'] as String;
          return NotebookNote(
            id: id,
            title: row['title'] as String,
            workspace: row['workspace'] as String? ?? _defaultWorkspaceName,
            notebook: row['notebook'] as String? ?? _defaultNotebookName,
            category: row['category'] as String,
            createdAt: DateTime.parse(row['created_at'] as String),
            updatedAt: DateTime.parse(row['updated_at'] as String),
            rawContent: row['raw_content'] as String,
            versions: versionsByNoteId[id] ?? const [],
          );
        })
        .toList(growable: false);
  }
}

ModelMode _modelModeFromName(String? value) {
  return ModelMode.values.firstWhere(
    (mode) => mode.name == value,
    orElse: () => ModelMode.localFast,
  );
}
