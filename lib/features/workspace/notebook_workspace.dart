import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../models/notebook_models.dart';
import '../../services/ai_command_service.dart';
import '../../services/authoring_directive_service.dart';
import '../../services/mock_enhancement_engine.dart';
import '../../services/note_parser.dart';
import '../../services/notebook_repository.dart';

enum EditorFontFamily { modern, editorial, mono }

class EditorAppearance {
  const EditorAppearance({
    required this.fontFamily,
    required this.fontSize,
    required this.isBold,
    required this.isItalic,
    required this.textColor,
  });

  final EditorFontFamily fontFamily;
  final double fontSize;
  final bool isBold;
  final bool isItalic;
  final Color textColor;

  EditorAppearance copyWith({
    EditorFontFamily? fontFamily,
    double? fontSize,
    bool? isBold,
    bool? isItalic,
    Color? textColor,
  }) {
    return EditorAppearance(
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      textColor: textColor ?? this.textColor,
    );
  }
}

class _NotebookRailGroup {
  const _NotebookRailGroup({required this.label, required this.notes});

  final String label;
  final List<NotebookNote> notes;
}

class _MoveNoteResult {
  const _MoveNoteResult({required this.workspace, required this.notebook});

  final String workspace;
  final String notebook;
}

enum _NoteAction { rename, move, delete }

class NotebookWorkspace extends StatefulWidget {
  const NotebookWorkspace({
    super.key,
    required this.engine,
    required this.repository,
    required this.settings,
    required this.onSaveSettings,
    this.initialNotes,
  });

  final MockEnhancementEngine engine;
  final NotebookRepository repository;
  final AppSettings settings;
  final Future<void> Function(AppSettings settings) onSaveSettings;
  final List<NotebookNote>? initialNotes;

  @override
  State<NotebookWorkspace> createState() => _NotebookWorkspaceState();
}

class _NotebookWorkspaceState extends State<NotebookWorkspace> {
  static const _allWorkspacesLabel = 'All workspaces';
  static const _allNotebooksLabel = 'All notebooks';
  static const _defaultWorkspace = 'Personal';
  static const _defaultNotebook = 'Inbox';
  final _controller = TextEditingController();
  final _searchController = TextEditingController();
  final _notesRailScrollController = ScrollController();
  final _editorFocusNode = FocusNode();
  static const _authoringDirectiveService = AuthoringDirectiveService();
  static const _aiCommandService = AiCommandService();
  static const _contentParser = NoteParser();

  List<NotebookNote> _notes = const [];
  NotebookNote? _selectedNote;
  EnhancementSnapshot _snapshot = const EnhancementSnapshot(
    enhancedContent: 'Your enhanced note will appear here as you type.',
    summary:
        'Start writing in the raw pane to see structure, cleanup, and verification hints.',
    changes: [],
    flags: [],
    routePlan: RoutePlan(
      execution: RouteExecution.deterministicOnly,
      riskLevel: NoteRiskLevel.low,
      summary: 'Waiting for note content.',
    ),
  );
  Timer? _enhancementDebounce;
  Timer? _persistDebounce;
  ModelMode _mode = ModelMode.localFast;
  ProcessorToggles _toggles = const ProcessorToggles(
    spelling: true,
    formatting: true,
    clarity: true,
    verification: true,
  );
  EditorAppearance _editorAppearance = const EditorAppearance(
    fontFamily: EditorFontFamily.modern,
    fontSize: 17,
    isBold: false,
    isItalic: false,
    textColor: Color(0xFF18171A),
  );
  bool _isLoading = true;
  bool _isProcessing = false;
  String? _loadError;
  String _searchQuery = '';
  String _selectedWorkspaceFilter = _allWorkspacesLabel;
  String _selectedNotebookFilter = _allNotebooksLabel;
  int _enhancementRevision = 0;
  int _aiCommandRevision = 0;
  Map<String, AiCommandResult> _aiCommandResults = const {};
  String? _activeAiCommandId;

  @override
  void initState() {
    super.initState();
    if (widget.initialNotes case final notes?) {
      _hydrateLoadedNotes(notes);
    } else {
      _loadNotes();
    }
  }

  @override
  void dispose() {
    _enhancementDebounce?.cancel();
    _persistDebounce?.cancel();
    _editorFocusNode.dispose();
    _controller.dispose();
    _searchController.dispose();
    _notesRailScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_loadError case final message?) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(message, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final selectedNote = _selectedNote;
    if (selectedNote == null) {
      return const Scaffold(
        body: Center(child: Text('No notes available yet.')),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 1100;
              final compactNotesRailHeight = _compactNotesRailHeight(
                constraints.maxHeight,
              );
              final content = compact
                  ? Column(
                      children: [
                        _buildTopBar(
                          context,
                          compact: true,
                          selected: selectedNote,
                        ),
                        const SizedBox(height: 20),
                        Expanded(
                          child: _buildEditorColumn(
                            context,
                            compact: true,
                            selected: selectedNote,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 280,
                          child: _buildNotesRail(
                            context,
                            selected: selectedNote,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            children: [
                              _buildTopBar(
                                context,
                                compact: false,
                                selected: selectedNote,
                              ),
                              const SizedBox(height: 20),
                              Expanded(
                                child: _buildEditorColumn(
                                  context,
                                  compact: false,
                                  selected: selectedNote,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );

              return DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF8F5EE), Color(0xFFE9F0EC)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: compact
                      ? Column(
                          children: [
                            SizedBox(
                              height: compactNotesRailHeight,
                              child: _buildNotesRail(
                                context,
                                compact: true,
                                selected: selectedNote,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Expanded(child: content),
                          ],
                        )
                      : content,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context, {
    required bool compact,
    required NotebookNote selected,
  }) {
    final theme = Theme.of(context);
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          selected.title,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Raw notes stay untouched. The enhanced pane updates with explainable changes.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF5B605F),
          ),
        ),
      ],
    );
    final modeSwitcher = SegmentedButton<ModelMode>(
      segments: const [
        ButtonSegment(
          value: ModelMode.localFast,
          label: Text('Local Fast'),
          icon: Icon(Icons.bolt_outlined),
        ),
        ButtonSegment(
          value: ModelMode.cloudAccurate,
          label: Text('Cloud Accurate'),
          icon: Icon(Icons.cloud_outlined),
        ),
      ],
      selected: {_mode},
      onSelectionChanged: (selection) {
        setState(() {
          _mode = selection.first;
          _aiCommandResults = const {};
          _activeAiCommandId = null;
        });
        unawaited(_refreshNoteProcessing(_controller.text));
        _persistCurrentVersion();
      },
    );

    final settingsButton = FilledButton.tonalIcon(
      onPressed: _openSettingsDialog,
      icon: const Icon(Icons.tune),
      label: const Text('Settings'),
    );
    final aiDrawerButton = FilledButton.tonalIcon(
      onPressed: _openAiDrawer,
      icon: const Icon(Icons.auto_awesome_outlined),
      label: Text(_visibleAiCommandResults.isEmpty ? 'AI Guide' : 'AI Drawer'),
    );
    final noteActionsButton = PopupMenuButton<_NoteAction>(
      key: const ValueKey('selected-note-actions-button'),
      tooltip: 'Note actions',
      onSelected: (action) => _handleNoteActionForSelected(action),
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _NoteAction.rename,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.drive_file_rename_outline),
            title: Text('Rename note'),
          ),
        ),
        PopupMenuItem(
          value: _NoteAction.move,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.folder_open_outlined),
            title: Text('Move note'),
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: _NoteAction.delete,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline),
            title: Text('Delete note'),
          ),
        ),
      ],
      child: const Padding(
        padding: EdgeInsets.all(8),
        child: Icon(Icons.more_horiz),
      ),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleBlock,
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                modeSwitcher,
                const SizedBox(width: 12),
                aiDrawerButton,
                const SizedBox(width: 12),
                settingsButton,
                const SizedBox(width: 4),
                noteActionsButton,
              ],
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: titleBlock),
        const SizedBox(width: 16),
        modeSwitcher,
        const SizedBox(width: 12),
        aiDrawerButton,
        const SizedBox(width: 12),
        settingsButton,
        const SizedBox(width: 4),
        noteActionsButton,
      ],
    );
  }

  Widget _buildNotesRail(
    BuildContext context, {
    bool compact = false,
    required NotebookNote selected,
  }) {
    final theme = Theme.of(context);
    final filteredNotes = _filteredNotes;
    final railGroups = _filteredRailGroups;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD8DBD7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Library',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _createNewNote,
                  icon: const Icon(Icons.add),
                  label: Text(compact ? 'Add' : 'New'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.trim().toLowerCase();
                });
              },
              decoration: InputDecoration(
                hintText: 'Search notes',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                        icon: const Icon(Icons.close),
                      ),
                filled: true,
                fillColor: const Color(0xFFF4F6F3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 14),
            _buildScopeChips(
              label: 'Workspace',
              options: _workspaceFilters,
              selectedValue: _selectedWorkspaceFilter,
              onSelected: _setWorkspaceFilter,
            ),
            const SizedBox(height: 10),
            _buildScopeChips(
              label: 'Notebook',
              options: _notebookFilters,
              selectedValue: _selectedNotebookFilter,
              onSelected: _setNotebookFilter,
            ),
            const SizedBox(height: 18),
            Expanded(
              child: filteredNotes.isEmpty
                  ? _buildEmptySearchState(theme.textTheme)
                  : Scrollbar(
                      controller: _notesRailScrollController,
                      thumbVisibility: !compact,
                      child: compact
                          ? ListView.separated(
                              key: const PageStorageKey<String>(
                                'notes-rail-compact',
                              ),
                              controller: _notesRailScrollController,
                              primary: false,
                              scrollDirection: Axis.horizontal,
                              itemCount: filteredNotes.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (context, index) {
                                final note = filteredNotes[index];
                                return SizedBox(
                                  width: 220,
                                  child: _buildNoteRailCard(
                                    context,
                                    note: note,
                                    selected: selected.id == note.id,
                                  ),
                                );
                              },
                            )
                          : ListView.separated(
                              key: const PageStorageKey<String>(
                                'notes-rail-desktop',
                              ),
                              controller: _notesRailScrollController,
                              primary: false,
                              itemCount: railGroups.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 16),
                              itemBuilder: (context, index) {
                                final group = railGroups[index];
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      group.label,
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: const Color(0xFF46504D),
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    ...group.notes.map(
                                      (note) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        child: _buildNoteRailCard(
                                          context,
                                          note: note,
                                          selected: selected.id == note.id,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorColumn(
    BuildContext context, {
    required bool compact,
    required NotebookNote selected,
  }) {
    if (compact) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final shouldScrollPanels = constraints.maxHeight < 720;
          if (!shouldScrollPanels) {
            return Column(
              children: [
                Expanded(child: _buildRawPane(context)),
                const SizedBox(height: 16),
                Expanded(
                  child: _buildEnhancedPane(context, selected: selected),
                ),
              ],
            );
          }

          final panelHeight = constraints.maxHeight < 520
              ? 520.0
              : constraints.maxHeight.clamp(520.0, 640.0);
          return SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(height: panelHeight, child: _buildRawPane(context)),
                const SizedBox(height: 16),
                SizedBox(
                  height: panelHeight,
                  child: _buildEnhancedPane(context, selected: selected),
                ),
              ],
            ),
          );
        },
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildRawPane(context)),
        const SizedBox(width: 16),
        Expanded(child: _buildEnhancedPane(context, selected: selected)),
      ],
    );
  }

  Widget _buildRawPane(BuildContext context) {
    final theme = Theme.of(context);
    return _panelShell(
      context,
      title: 'Raw',
      subtitle: 'Fast capture. No silent rewrites.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tightHeight = constraints.maxHeight < 400;
          final editor = TextField(
            focusNode: _editorFocusNode,
            controller: _controller,
            onChanged: _handleRawEditorChanged,
            expands: !tightHeight,
            minLines: tightHeight ? 10 : null,
            maxLines: tightHeight ? null : null,
            style: _editorTextStyle(theme),
            decoration: InputDecoration(
              hintText:
                  'Capture rough thoughts, meeting notes, research scraps...',
              filled: true,
              fillColor: const Color(0xFFFFFCF6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: const BorderSide(color: Color(0xFFDBDFD8)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: const BorderSide(color: Color(0xFFDBDFD8)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: const BorderSide(
                  color: Color(0xFF167C80),
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.all(18),
            ),
          );

          if (tightHeight) {
            return SingleChildScrollView(
              child: Column(
                children: [
                  _buildRawPaneControls(),
                  const SizedBox(height: 16),
                  SizedBox(height: 260, child: editor),
                ],
              ),
            );
          }

          return Column(
            children: [
              _buildRawPaneControls(),
              const SizedBox(height: 16),
              Expanded(child: editor),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRawPaneControls() {
    return Column(
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _processorChip(
              label: 'Spelling',
              value: _toggles.spelling,
              onChanged: (value) =>
                  _updateToggles(_toggles.copyWith(spelling: value)),
            ),
            _processorChip(
              label: 'Formatting',
              value: _toggles.formatting,
              onChanged: (value) =>
                  _updateToggles(_toggles.copyWith(formatting: value)),
            ),
            _processorChip(
              label: 'Clarity',
              value: _toggles.clarity,
              onChanged: (value) =>
                  _updateToggles(_toggles.copyWith(clarity: value)),
            ),
            _processorChip(
              label: 'Verification',
              value: _toggles.verification,
              onChanged: (value) =>
                  _updateToggles(_toggles.copyWith(verification: value)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildWriterToolbar(context),
      ],
    );
  }

  Widget _buildWriterToolbar(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5EFE1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3D4B3)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<EditorFontFamily>(
              initialValue: _editorAppearance.fontFamily,
              isExpanded: true,
              decoration: _toolbarFieldDecoration('Font'),
              items: EditorFontFamily.values
                  .map(
                    (family) => DropdownMenuItem(
                      value: family,
                      child: Text(_fontFamilyLabel(family)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _editorAppearance = _editorAppearance.copyWith(
                    fontFamily: value,
                  );
                });
              },
            ),
          ),
          SizedBox(
            width: 110,
            child: DropdownButtonFormField<double>(
              initialValue: _editorAppearance.fontSize,
              isExpanded: true,
              decoration: _toolbarFieldDecoration('Size'),
              items: const [
                DropdownMenuItem(value: 15.0, child: Text('15 pt')),
                DropdownMenuItem(value: 17.0, child: Text('17 pt')),
                DropdownMenuItem(value: 20.0, child: Text('20 pt')),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _editorAppearance = _editorAppearance.copyWith(
                    fontSize: value,
                  );
                });
              },
            ),
          ),
          _toolbarToggleButton(
            icon: Icons.format_bold,
            label: 'Bold',
            selected: _editorAppearance.isBold,
            onPressed: () {
              setState(() {
                _editorAppearance = _editorAppearance.copyWith(
                  isBold: !_editorAppearance.isBold,
                );
              });
            },
          ),
          _toolbarToggleButton(
            icon: Icons.format_italic,
            label: 'Italic',
            selected: _editorAppearance.isItalic,
            onPressed: () {
              setState(() {
                _editorAppearance = _editorAppearance.copyWith(
                  isItalic: !_editorAppearance.isItalic,
                );
              });
            },
          ),
          Wrap(
            spacing: 8,
            children: [
              _colorSwatch(const Color(0xFF18171A), 'Ink'),
              _colorSwatch(const Color(0xFF314652), 'Slate'),
              _colorSwatch(const Color(0xFF0F5B53), 'Forest'),
            ],
          ),
          _toolbarActionButton(
            icon: Icons.title,
            label: 'Heading',
            onPressed: () => _insertSnippet('# '),
          ),
          _toolbarActionButton(
            icon: Icons.format_list_bulleted,
            label: 'Bullet',
            onPressed: () => _insertSnippet('- '),
          ),
          _toolbarActionButton(
            icon: Icons.check_box_outlined,
            label: 'Checklist',
            onPressed: () => _insertSnippet('- [ ] '),
          ),
          _toolbarActionButton(
            icon: Icons.calculate_outlined,
            label: 'Math',
            onPressed: _insertMathBlock,
          ),
          _toolbarActionButton(
            icon: Icons.table_chart_outlined,
            label: 'Table',
            onPressed: _insertTableBlock,
          ),
          Text(
            'Writer tools',
            style: theme.textTheme.labelMedium?.copyWith(
              color: const Color(0xFF715A2A),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedPane(
    BuildContext context, {
    required NotebookNote selected,
  }) {
    final theme = Theme.of(context);
    return _panelShell(
      context,
      title: 'Enhanced',
      subtitle: _mode == ModelMode.localFast
          ? 'Low-latency cleanup powered by local processing.'
          : 'Higher-confidence pass prepared for cloud-backed verification.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildEnhancedArtifactsSection(context),
                  const SizedBox(height: 12),
                  _buildRoutePlanCard(context),
                  const SizedBox(height: 12),
                  _buildProcessorStatusRow(context),
                  const SizedBox(height: 16),
                  _buildEnhancedContentCard(context, theme),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stackCards = constraints.maxWidth < 700;
                      if (stackCards) {
                        return Column(
                          children: [
                            _buildChangesCard(context),
                            const SizedBox(height: 14),
                            _buildVerificationCard(context, selected: selected),
                            const SizedBox(height: 14),
                            _buildVersionHistoryCard(
                              context,
                              selected: selected,
                            ),
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildChangesCard(context)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _buildVerificationCard(
                              context,
                              selected: selected,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _buildVersionHistoryCard(
                              context,
                              selected: selected,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEnhancedContentCard(BuildContext context, ThemeData theme) {
    final structure = _contentParser.parse(_snapshot.enhancedContent);
    final hasStructuredBlocks = structure.blocks.any(
      (block) => block.kind == BlockKind.math || block.kind == BlockKind.table,
    );

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 280),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD8DBD7)),
      ),
      child: hasStructuredBlocks
          ? _buildEnhancedStructuredContent(context, theme, structure)
          : SelectableText(
              _snapshot.enhancedContent,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
            ),
    );
  }

  Widget _buildEnhancedStructuredContent(
    BuildContext context,
    ThemeData theme,
    NoteStructure structure,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < structure.blocks.length; index++) ...[
          _buildEnhancedBlock(context, theme, structure.blocks[index]),
          if (index != structure.blocks.length - 1) const SizedBox(height: 18),
        ],
      ],
    );
  }

  Widget _buildEnhancedBlock(
    BuildContext context,
    ThemeData theme,
    BlockNode block,
  ) {
    if (block.kind == BlockKind.math) {
      return _buildEnhancedMathBlock(context, theme, block);
    }
    if (block.kind == BlockKind.table) {
      return _buildEnhancedTableBlock(context, theme, block);
    }

    final text = block.lines
        .map((line) => line.sourceLine.trimRight())
        .join('\n')
        .trimRight();
    return SelectableText(
      text,
      style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
    );
  }

  Widget _buildEnhancedMathBlock(
    BuildContext context,
    ThemeData theme,
    BlockNode block,
  ) {
    final expression = block.lines
        .where((line) => !_isMathDirectiveLine(line))
        .map((line) => line.sourceLine.trimRight())
        .where((line) => line.isNotEmpty)
        .join('\n')
        .trim();

    if (expression.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F4EC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1D7C6)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Math.tex(
          expression,
          mathStyle: MathStyle.display,
          textStyle: theme.textTheme.bodyLarge?.copyWith(fontSize: 22),
        ),
      ),
    );
  }

  bool _isMathDirectiveLine(LineNode line) {
    final trimmed = line.trimmed;
    return line.kind == LineKind.directive &&
        (trimmed == '/math' || trimmed == '/end');
  }

  Widget _buildEnhancedTableBlock(
    BuildContext context,
    ThemeData theme,
    BlockNode block,
  ) {
    final rows = block.lines
        .where((line) => !_isTableDirectiveLine(line))
        .map((line) => _parseTableRow(line.sourceLine))
        .whereType<List<String>>()
        .toList(growable: false);

    if (rows.isEmpty) {
      final fallbackText = block.lines
          .map((line) => line.sourceLine.trimRight())
          .join('\n')
          .trimRight();
      return SelectableText(
        fallbackText,
        style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
      );
    }

    final normalizedRows = _normalizeTableRows(rows);
    final hasDividerRow =
        normalizedRows.length > 1 && _isDividerRow(normalizedRows[1]);
    final header = normalizedRows.first;
    final bodyRows = hasDividerRow
        ? normalizedRows.skip(2).toList(growable: false)
        : normalizedRows.skip(1).toList(growable: false);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD9E2EC)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(color: const Color(0xFFD9E2EC)),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: const BoxDecoration(color: Color(0xFFEAF2F8)),
              children: [
                for (final cell in header)
                  _buildTableCell(context, cell, isHeader: true, theme: theme),
              ],
            ),
            for (final row in bodyRows)
              TableRow(
                children: [
                  for (final cell in row)
                    _buildTableCell(context, cell, theme: theme),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableCell(
    BuildContext context,
    String value, {
    required ThemeData theme,
    bool isHeader = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: SelectableText(
        value,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: isHeader ? FontWeight.w700 : FontWeight.w500,
          color: isHeader ? const Color(0xFF183041) : null,
        ),
      ),
    );
  }

  List<List<String>> _normalizeTableRows(List<List<String>> rows) {
    final columnCount = rows.fold<int>(
      0,
      (current, row) => row.length > current ? row.length : current,
    );
    return rows
        .map(
          (row) => [
            ...row,
            for (var index = row.length; index < columnCount; index++) '',
          ],
        )
        .toList(growable: false);
  }

  List<String>? _parseTableRow(String rawLine) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty || !trimmed.contains('|')) {
      return null;
    }

    final stripped = trimmed.startsWith('|') ? trimmed.substring(1) : trimmed;
    final withoutTrailing = stripped.endsWith('|')
        ? stripped.substring(0, stripped.length - 1)
        : stripped;
    final cells = withoutTrailing
        .split('|')
        .map((cell) => cell.trim())
        .toList(growable: false);

    if (cells.length < 2) {
      return null;
    }
    return cells;
  }

  bool _isDividerRow(List<String> row) {
    return row.every(
      (cell) => cell.isNotEmpty && RegExp(r'^:?-{3,}:?$').hasMatch(cell),
    );
  }

  bool _isTableDirectiveLine(LineNode line) {
    final trimmed = line.trimmed;
    return line.kind == LineKind.directive &&
        (trimmed == '/table' || trimmed == '/end');
  }

  Widget _buildEnhancedArtifactsSection(BuildContext context) {
    final summary = _snapshot.summary.trim();
    final suggestedTitle = _snapshotSuggestedTitle;
    final actionItems = _snapshotActionItems;
    final commandResults = _visibleAiCommandResults;
    final hasSummary = summary.isNotEmpty;
    final hasSidecars = suggestedTitle != null || actionItems.isNotEmpty;
    final hasCommandResults = commandResults.isNotEmpty;

    if (!hasSummary && !hasSidecars && !hasCommandResults) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasSummary) _buildSummaryArtifactCard(context, summary),
        if (hasSidecars) ...[
          if (hasSummary) const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = <Widget>[
                if (suggestedTitle != null)
                  _buildArtifactCard(
                    context,
                    title: 'Suggested title',
                    backgroundColor: const Color(0xFFF6F0E4),
                    borderColor: const Color(0xFFE0D0AE),
                    child: SelectableText(
                      suggestedTitle,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (actionItems.isNotEmpty)
                  _buildArtifactCard(
                    context,
                    title: 'Action items',
                    backgroundColor: const Color(0xFFF4F3FA),
                    borderColor: const Color(0xFFD8D2EE),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: actionItems
                          .map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    margin: const EdgeInsets.only(
                                      top: 6,
                                      right: 10,
                                    ),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF4C5682),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      item,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(height: 1.35),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
              ];

              if (cards.length < 2 || constraints.maxWidth < 760) {
                return Column(
                  children: [
                    for (var index = 0; index < cards.length; index++) ...[
                      cards[index],
                      if (index != cards.length - 1) const SizedBox(height: 12),
                    ],
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < cards.length; index++) ...[
                    Expanded(child: cards[index]),
                    if (index != cards.length - 1) const SizedBox(width: 12),
                  ],
                ],
              );
            },
          ),
        ],
        if (hasCommandResults) ...[
          if (hasSummary || hasSidecars) const SizedBox(height: 12),
          _buildAiCommandResultsCard(context, commandResults),
        ],
      ],
    );
  }

  Widget _buildSummaryArtifactCard(BuildContext context, String summary) {
    return _buildArtifactCard(
      context,
      title: 'Summary',
      backgroundColor: const Color(0xFFE5F1EC),
      borderColor: const Color(0xFFC8DED6),
      child: Text(
        summary,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.35),
      ),
    );
  }

  Widget _buildArtifactCard(
    BuildContext context, {
    required String title,
    required Color backgroundColor,
    required Color borderColor,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: const Color(0xFF304745),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _buildAiCommandResultsCard(
    BuildContext context,
    List<AiCommandResult> results,
  ) {
    final theme = Theme.of(context);
    return _buildArtifactCard(
      context,
      title: 'AI Requests',
      backgroundColor: const Color(0xFFEAF1F8),
      borderColor: const Color(0xFFC9D8EA),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < results.length; index++) ...[
            _buildAiCommandResultPreview(context, results[index], theme),
            if (index != results.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildAiCommandResultPreview(
    BuildContext context,
    AiCommandResult result,
    ThemeData theme,
  ) {
    final preview = result.content.trim().isEmpty
        ? result.detail
        : _compactPreview(result.content);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              result.request.displayLabel,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            _buildAiCommandStatusChip(result),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          preview,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 520;
            final providerText = Text(
              result.providerLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF51606A),
              ),
            );
            final actionButtons = Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (_canApplyAiResult(result))
                  TextButton(
                    key: ValueKey('insert-ai-result-${result.request.id}'),
                    onPressed: () => _insertAiResultAtCursor(result),
                    child: const Text('Insert'),
                  ),
                if (_canApplyAiResult(result))
                  TextButton(
                    key: ValueKey('append-ai-result-${result.request.id}'),
                    onPressed: () => _appendAiResultBelow(result),
                    child: const Text('Append below'),
                  ),
                TextButton(
                  onPressed: () => _openAiDrawer(result.request.id),
                  child: const Text('Open AI Drawer'),
                ),
              ],
            );

            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  providerText,
                  Align(alignment: Alignment.centerRight, child: actionButtons),
                ],
              );
            }

            return Row(children: [providerText, const Spacer(), actionButtons]);
          },
        ),
      ],
    );
  }

  Widget _buildAiCommandStatusChip(AiCommandResult result) {
    final (background, foreground, label) = switch (result.status) {
      AiCommandStatus.running => (
        const Color(0xFFE7F3E9),
        const Color(0xFF1F6A3C),
        'Running',
      ),
      AiCommandStatus.completed => (
        const Color(0xFFE5F1EC),
        const Color(0xFF245F50),
        'Ready',
      ),
      AiCommandStatus.unavailable => (
        const Color(0xFFFFF0DF),
        const Color(0xFF8A5A10),
        'Unavailable',
      ),
      AiCommandStatus.failed => (
        const Color(0xFFFBE6E8),
        const Color(0xFFA23445),
        'Error',
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildChangesCard(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9EE),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4D7B8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Change Log',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (_snapshot.changes.isEmpty)
            Text(
              'No changes yet. Start typing to trigger the enhancement pipeline.',
              style: theme.textTheme.bodyMedium,
            )
          else
            ..._snapshot.changes.map(
              (change) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(_iconForChange(change.type), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            change.label,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(change.description),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProcessorStatusRow(BuildContext context) {
    final theme = Theme.of(context);
    final statuses = _snapshot.processorStatuses;
    if (statuses.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: statuses.map((status) {
        final color = switch (status.state) {
          ProcessorState.completed => const Color(0xFFDCEFE6),
          ProcessorState.skipped => const Color(0xFFEAEDEF),
          ProcessorState.unavailable => const Color(0xFFF4E7C9),
          ProcessorState.failed => const Color(0xFFF6D8D8),
        };
        final textColor = switch (status.state) {
          ProcessorState.completed => const Color(0xFF1C5B49),
          ProcessorState.skipped => const Color(0xFF55626D),
          ProcessorState.unavailable => const Color(0xFF8A5A17),
          ProcessorState.failed => const Color(0xFF8A2424),
        };

        return Tooltip(
          message: status.detail,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${status.label}: ${_statusLabel(status.state)}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRoutePlanCard(BuildContext context) {
    final theme = Theme.of(context);
    final routePlan = _snapshot.routePlan;
    final (backgroundColor, borderColor, label) = switch (routePlan.execution) {
      RouteExecution.local => (
        const Color(0xFFEAF3FF),
        const Color(0xFFC9D9F6),
        'Route: Local bounded',
      ),
      RouteExecution.deterministicOnly => (
        const Color(0xFFF7F1E8),
        const Color(0xFFE2D2B9),
        'Route: Deterministic only',
      ),
      RouteExecution.deferredCloud => (
        const Color(0xFFF3EDF9),
        const Color(0xFFD8CDEE),
        'Route: Deferred cloud',
      ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            routePlan.summary,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationCard(
    BuildContext context, {
    required NotebookNote selected,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F2F6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD8C9D7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Verification',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (_snapshot.flags.isEmpty)
            Text(
              'No fact-check warnings for this note right now.',
              style: theme.textTheme.bodyMedium,
            )
          else
            ..._snapshot.flags.map(
              (flag) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      flag.claimText,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(flag.note),
                    const SizedBox(height: 4),
                    Text(
                      'Confidence ${flag.confidence.toStringAsFixed(2)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF63606A),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVersionHistoryCard(
    BuildContext context, {
    required NotebookNote selected,
  }) {
    final theme = Theme.of(context);
    final versions = selected.versions.reversed.take(4).toList(growable: false);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FA),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFC8D4EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'History',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${selected.versions.length} snapshots saved',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF4E607C),
            ),
          ),
          const SizedBox(height: 12),
          if (versions.isEmpty)
            Text(
              'Snapshots will appear after the first enhancement run.',
              style: theme.textTheme.bodyMedium,
            )
          else
            ...versions.map(
              (version) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            color: version.modelMode == ModelMode.localFast
                                ? const Color(0xFF167C80)
                                : const Color(0xFF4472C4),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _versionLabel(version),
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                version.rawContent.trim().isEmpty
                                    ? 'Empty raw capture'
                                    : version.rawContent
                                          .trim()
                                          .split('\n')
                                          .first,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton(
                          key: ValueKey('restore-raw-${version.id}'),
                          onPressed: () => _restoreVersionRaw(version),
                          child: const Text('Restore raw'),
                        ),
                        if (version.enhancedContent.trim().isNotEmpty)
                          TextButton(
                            key: ValueKey('insert-enhanced-${version.id}'),
                            onPressed: () =>
                                _insertVersionEnhancedAtCursor(version),
                            child: const Text('Insert enhanced'),
                          ),
                        if (version.enhancedContent.trim().isNotEmpty)
                          TextButton(
                            key: ValueKey('append-enhanced-${version.id}'),
                            onPressed: () =>
                                _appendVersionEnhancedBelow(version),
                            child: const Text('Append enhanced'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _panelShell(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFD8DBD7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF5B605F),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  Widget _processorChip({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return FilterChip(
      selected: value,
      label: Text(label),
      onSelected: onChanged,
      selectedColor: const Color(0xFFD4EBE7),
      checkmarkColor: const Color(0xFF114A47),
      labelStyle: TextStyle(
        color: value ? const Color(0xFF114A47) : const Color(0xFF5B605F),
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildEmptySearchState(TextTheme theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_outlined, size: 28),
            const SizedBox(height: 10),
            Text(
              'No notes match this search yet.',
              textAlign: TextAlign.center,
              style: theme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Try another title, workspace, notebook, or category keyword.',
              textAlign: TextAlign.center,
              style: theme.bodyMedium?.copyWith(color: const Color(0xFF5B605F)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScopeChips({
    required String label,
    required List<String> options,
    required String selectedValue,
    required ValueChanged<String> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF5B605F),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: options
                .map(
                  (option) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: selectedValue == option,
                      onSelected: (_) => onSelected(option),
                      selectedColor: const Color(0xFFD4EBE7),
                      checkmarkColor: const Color(0xFF114A47),
                      label: Text(option),
                      labelStyle: TextStyle(
                        color: selectedValue == option
                            ? const Color(0xFF114A47)
                            : const Color(0xFF5B605F),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ],
    );
  }

  Widget _buildNoteRailCard(
    BuildContext context, {
    required NotebookNote note,
    required bool selected,
  }) {
    final theme = Theme.of(context);
    final actionsButton = PopupMenuButton<_NoteAction>(
      key: ValueKey('note-actions-${note.id}'),
      tooltip: 'Note actions',
      onSelected: (action) => _handleNoteAction(action, note),
      itemBuilder: (context) => const [
        PopupMenuItem(value: _NoteAction.rename, child: Text('Rename')),
        PopupMenuItem(value: _NoteAction.move, child: Text('Move')),
        PopupMenuDivider(),
        PopupMenuItem(value: _NoteAction.delete, child: Text('Delete')),
      ],
      icon: Icon(
        Icons.more_horiz,
        color: selected ? Colors.white70 : const Color(0xFF5B605F),
      ),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _selectNote(note),
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF153D44) : const Color(0xFFF6F6F1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0xFF153D44) : const Color(0xFFE2E4DE),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _noteScopeLabel(note),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: selected
                          ? Colors.white70
                          : const Color(0xFF5B605F),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                actionsButton,
              ],
            ),
            Text(
              note.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : null,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${note.category} • ${_relativeDate(note.updatedAt)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: selected ? Colors.white70 : const Color(0xFF7B817F),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _toolbarFieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD7D4CB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD7D4CB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF167C80), width: 1.2),
      ),
    );
  }

  Widget _toolbarToggleButton({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onPressed,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFDCEFE6) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFF167C80) : const Color(0xFFD7D4CB),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: const Color(0xFF29403F)),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
      ),
    );
  }

  Widget _toolbarActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  Widget _colorSwatch(Color color, String tooltip) {
    final selected = _editorAppearance.textColor == color;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          setState(() {
            _editorAppearance = _editorAppearance.copyWith(textColor: color);
          });
        },
        child: Ink(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? const Color(0xFF167C80) : Colors.white,
              width: selected ? 2.4 : 1.4,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadNotes() async {
    try {
      final notes = await widget.repository.loadNotes();
      _hydrateLoadedNotes(notes);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _loadError = 'Unable to load notes: $error';
      });
    }
  }

  void _hydrateLoadedNotes(List<NotebookNote> notes) {
    final selected = notes.firstOrNull;
    if (!mounted) {
      return;
    }

    setState(() {
      _notes = notes;
      _selectedNote = selected;
      _controller.text = selected?.rawContent ?? '';
      _aiCommandResults = const {};
      _activeAiCommandId = null;
      _isLoading = false;
    });
    if (selected != null) {
      unawaited(_refreshNoteProcessing(selected.rawContent));
    }
  }

  void _queueEnhancement(String value) {
    final selected = _selectedNote;
    if (selected == null) {
      return;
    }

    _enhancementDebounce?.cancel();
    _persistDebounce?.cancel();

    final updatedNote = selected.copyWith(
      rawContent: value,
      updatedAt: DateTime.now(),
    );

    setState(() {
      _selectedNote = updatedNote;
      _notes = _replaceNote(updatedNote);
    });

    _enhancementDebounce = Timer(
      const Duration(milliseconds: 450),
      _refreshEnhancement,
    );
  }

  void _handleRawEditorChanged(String value) {
    final selected = _selectedNote;
    if (selected == null) {
      return;
    }

    final expansion = _authoringDirectiveService.expandTrailingShortcut(
      previousText: selected.rawContent,
      nextText: value,
      selectionOffset: _controller.selection.extentOffset,
    );
    if (expansion == null) {
      _queueEnhancement(value);
      return;
    }

    _controller.value = _controller.value.copyWith(
      text: expansion.text,
      selection: TextSelection.collapsed(offset: expansion.selectionOffset),
      composing: TextRange.empty,
    );
    _queueEnhancement(expansion.text);
  }

  Future<void> _refreshNoteProcessing(String rawContent) async {
    await _runEnhancement(rawContent);
    await _syncAiCommands(rawContent);
  }

  Future<void> _syncAiCommands(String rawContent) async {
    if (!mounted) {
      return;
    }

    final selectedNoteId = _selectedNote?.id;
    if (selectedNoteId == null) {
      return;
    }

    final commands = _aiCommandService.parseCommands(rawContent);
    final activeIds = commands.map((command) => command.id).toSet();
    final requestRevision = ++_aiCommandRevision;
    final strippedContent = _aiCommandService.stripCommandLines(rawContent);

    final nextResults = <String, AiCommandResult>{};
    for (final command in commands) {
      final existing = _aiCommandResults[command.id];
      nextResults[command.id] =
          existing ??
          AiCommandResult(
            request: command,
            status: AiCommandStatus.running,
            title: command.resultTitle,
            content: '',
            detail: 'Waiting for an explicit AI response.',
            providerLabel: _providerLabelForMode(_mode),
          );
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _aiCommandResults = nextResults;
      if (_activeAiCommandId != null &&
          !activeIds.contains(_activeAiCommandId)) {
        _activeAiCommandId = null;
      }
      _activeAiCommandId ??= commands.firstOrNull?.id;
    });

    final pending = commands
        .where((command) {
          final existing = _aiCommandResults[command.id];
          return existing == null || !existing.isTerminal;
        })
        .toList(growable: false);

    for (final command in pending) {
      final result = await _executeAiCommand(
        command: command,
        rawContent: strippedContent,
        requestRevision: requestRevision,
      );

      if (!_isCurrentAiCommandRun(
        rawContent: rawContent,
        requestRevision: requestRevision,
        selectedNoteId: selectedNoteId,
      )) {
        return;
      }

      setState(() {
        _aiCommandResults = {..._aiCommandResults, command.id: result};
        _activeAiCommandId ??= command.id;
      });
    }
  }

  Future<AiCommandResult> _executeAiCommand({
    required AiCommandRequest command,
    required String rawContent,
    required int requestRevision,
  }) async {
    final context = command.context.trim();
    if (context.isEmpty) {
      return AiCommandResult(
        request: command,
        status: AiCommandStatus.unavailable,
        title: command.resultTitle,
        content: '',
        detail: 'No nearby context matched this command yet.',
        providerLabel: _providerLabelForMode(_mode),
      );
    }

    if (_mode == ModelMode.cloudAccurate) {
      return widget.engine.cloudCommandAdapter.runAiCommand(
        request: EnhancementRequest(
          rawContent: rawContent,
          modelMode: _mode,
          toggles: _toggles,
          revisionId: requestRevision,
        ),
        command: command,
      );
    }

    return widget.engine.localModelAdapter.runAiCommand(
      request: EnhancementRequest(
        rawContent: rawContent,
        modelMode: _mode,
        toggles: _toggles,
        revisionId: requestRevision,
      ),
      command: command,
    );
  }

  bool _isCurrentAiCommandRun({
    required String rawContent,
    required int requestRevision,
    required String selectedNoteId,
  }) {
    return mounted &&
        requestRevision == _aiCommandRevision &&
        selectedNoteId == _selectedNote?.id &&
        rawContent == _controller.text;
  }

  Future<void> _refreshEnhancement() async {
    final selected = _selectedNote;
    if (selected == null) {
      return;
    }
    await _refreshNoteProcessing(_controller.text);
    _persistCurrentVersion();
  }

  void _selectNote(NotebookNote note) {
    setState(() {
      _selectedNote = note;
      _controller.text = note.rawContent;
      _aiCommandResults = const {};
      _activeAiCommandId = null;
    });
    unawaited(_refreshNoteProcessing(note.rawContent));
  }

  void _updateToggles(ProcessorToggles toggles) {
    setState(() {
      _toggles = toggles;
    });
    unawaited(_refreshNoteProcessing(_controller.text));
    _persistCurrentVersion();
  }

  void _setWorkspaceFilter(String workspace) {
    setState(() {
      _selectedWorkspaceFilter = workspace;
      if (workspace == _allWorkspacesLabel) {
        _selectedNotebookFilter = _allNotebooksLabel;
      } else if (_selectedNotebookFilter != _allNotebooksLabel &&
          !_notes.any(
            (note) =>
                note.workspace == workspace &&
                note.notebook == _selectedNotebookFilter,
          )) {
        _selectedNotebookFilter = _allNotebooksLabel;
      }
    });
    _syncSelectionToVisibleNotes();
  }

  void _setNotebookFilter(String notebook) {
    setState(() {
      _selectedNotebookFilter = notebook;
    });
    _syncSelectionToVisibleNotes();
  }

  void _cancelPendingNoteWork() {
    _persistDebounce?.cancel();
    _enhancementDebounce?.cancel();
  }

  Future<void> _handleNoteActionForSelected(_NoteAction action) async {
    final selected = _selectedNote;
    if (selected == null) {
      return;
    }
    await _handleNoteAction(action, selected);
  }

  Future<void> _handleNoteAction(_NoteAction action, NotebookNote note) async {
    switch (action) {
      case _NoteAction.rename:
        await _renameNote(note);
      case _NoteAction.move:
        await _moveNote(note);
      case _NoteAction.delete:
        await _deleteNote(note);
    }
  }

  Future<void> _renameNote(NotebookNote note) async {
    _cancelPendingNoteWork();
    final controller = TextEditingController(text: note.title);
    final updatedTitle = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename note'),
          content: TextField(
            key: const ValueKey('rename-note-field'),
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Note title',
              hintText: 'Lecture 04 - Limits',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    final normalizedTitle = updatedTitle?.trim();
    if (normalizedTitle == null || normalizedTitle.isEmpty) {
      return;
    }

    final renamed = note.copyWith(
      title: normalizedTitle,
      updatedAt: DateTime.now(),
    );
    await _commitNoteUpdate(renamed);
  }

  Future<void> _moveNote(NotebookNote note) async {
    _cancelPendingNoteWork();
    final workspaceController = TextEditingController(text: note.workspace);
    final notebookController = TextEditingController(text: note.notebook);
    final moveResult = await showDialog<_MoveNoteResult>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Move note'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const ValueKey('move-note-workspace-field'),
                  controller: workspaceController,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Workspace',
                    hintText: 'School',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const ValueKey('move-note-notebook-field'),
                  controller: notebookController,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Notebook',
                    hintText: 'General Study',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(
                  _MoveNoteResult(
                    workspace: workspaceController.text.trim(),
                    notebook: notebookController.text.trim(),
                  ),
                );
              },
              child: const Text('Move'),
            ),
          ],
        );
      },
    );

    if (moveResult == null ||
        moveResult.workspace.isEmpty ||
        moveResult.notebook.isEmpty) {
      return;
    }

    final moved = note.copyWith(
      workspace: moveResult.workspace,
      notebook: moveResult.notebook,
      updatedAt: DateTime.now(),
    );

    setState(() {
      _selectedWorkspaceFilter = moveResult.workspace;
      _selectedNotebookFilter = moveResult.notebook;
    });
    await _commitNoteUpdate(moved);
  }

  Future<void> _deleteNote(NotebookNote selected) async {
    _cancelPendingNoteWork();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete note'),
          content: Text(
            'Delete "${selected.title}"? Its saved snapshots will be removed too.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8A2424),
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final remaining = _notes
        .where((note) => note.id != selected.id)
        .toList(growable: false);
    final nextSelected = remaining.firstWhere(
      (note) => _isVisibleInCurrentScope(note),
      orElse: () => remaining.firstOrNull ?? _buildEmptyNote(),
    );
    final nextNotes = remaining.isEmpty ? [nextSelected] : remaining;

    setState(() {
      if (!nextNotes.any((note) => _isVisibleInCurrentScope(note))) {
        _selectedWorkspaceFilter = _allWorkspacesLabel;
        _selectedNotebookFilter = _allNotebooksLabel;
      }
      _notes = nextNotes;
      _selectedNote = nextSelected;
      _controller.text = nextSelected.rawContent;
      _aiCommandResults = const {};
      _activeAiCommandId = null;
    });
    await widget.repository.saveNotes(_notes);
    unawaited(_refreshNoteProcessing(nextSelected.rawContent));
  }

  bool _isVisibleInCurrentScope(NotebookNote note) {
    final workspaceVisible =
        _selectedWorkspaceFilter == _allWorkspacesLabel ||
        note.workspace == _selectedWorkspaceFilter;
    final notebookVisible =
        _selectedNotebookFilter == _allNotebooksLabel ||
        note.notebook == _selectedNotebookFilter;
    return workspaceVisible && notebookVisible;
  }

  Future<void> _commitNoteUpdate(NotebookNote updated) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _selectedNote = updated;
      _notes = _replaceNote(updated);
    });
    _syncSelectionToVisibleNotes();
    await widget.repository.saveNotes(_notes);
  }

  NotebookNote _buildEmptyNote() {
    final now = DateTime.now();
    return NotebookNote(
      id: 'note-${now.microsecondsSinceEpoch}',
      title: 'Untitled note 1',
      workspace: _defaultWorkspace,
      notebook: _defaultNotebook,
      category: 'General',
      createdAt: now,
      updatedAt: now,
      rawContent: '',
      versions: const [],
    );
  }

  void _syncSelectionToVisibleNotes() {
    final selected = _selectedNote;
    if (selected == null) {
      return;
    }

    if (_filteredNotes.any((note) => note.id == selected.id)) {
      return;
    }

    final fallback = _filteredNotes.firstOrNull;
    if (fallback == null) {
      return;
    }

    setState(() {
      _selectedNote = fallback;
      _controller.text = fallback.rawContent;
      _aiCommandResults = const {};
      _activeAiCommandId = null;
    });
    unawaited(_refreshNoteProcessing(fallback.rawContent));
  }

  Future<void> _createNewNote() async {
    final now = DateTime.now();
    final title = 'Untitled note ${_notes.length + 1}';
    final workspace = _selectedWorkspaceFilter == _allWorkspacesLabel
        ? (_selectedNote?.workspace ?? _defaultWorkspace)
        : _selectedWorkspaceFilter;
    final notebook = _selectedNotebookFilter == _allNotebooksLabel
        ? (_selectedNote?.notebook ?? _defaultNotebook)
        : _selectedNotebookFilter;
    final newNote = NotebookNote(
      id: 'note-${now.microsecondsSinceEpoch}',
      title: title,
      workspace: workspace,
      notebook: notebook,
      category: _selectedNote?.category ?? 'General',
      createdAt: now,
      updatedAt: now,
      rawContent: '',
      versions: const [],
    );

    setState(() {
      _selectedWorkspaceFilter = workspace;
      _selectedNotebookFilter = notebook;
      _notes = [newNote, ..._notes];
      _selectedNote = newNote;
      _controller.clear();
      _aiCommandResults = const {};
      _activeAiCommandId = null;
    });
    unawaited(_refreshNoteProcessing(''));

    await widget.repository.saveNotes(_notes);
  }

  void _persistCurrentVersion() {
    final selected = _selectedNote;
    if (selected == null) {
      return;
    }

    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 250), () async {
      final current = _selectedNote;
      if (current == null) {
        return;
      }

      final previousVersion = current.versions.lastOrNull;
      final shouldAppendVersion =
          previousVersion == null ||
          previousVersion.rawContent != current.rawContent ||
          previousVersion.enhancedContent != _snapshot.enhancedContent ||
          previousVersion.modelMode != _mode;

      final versions = shouldAppendVersion
          ? [
              ...current.versions,
              NotebookVersion(
                id: 'v-${DateTime.now().microsecondsSinceEpoch}',
                createdAt: DateTime.now(),
                rawContent: current.rawContent,
                enhancedContent: _snapshot.enhancedContent,
                modelMode: _mode,
              ),
            ]
          : current.versions;

      final persisted = current.copyWith(
        updatedAt: DateTime.now(),
        versions: versions,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedNote = persisted;
        _notes = _replaceNote(persisted);
      });
      await widget.repository.saveNotes(_notes);
    });
  }

  List<NotebookNote> _replaceNote(NotebookNote updated) {
    return _notes
        .map((note) => note.id == updated.id ? updated : note)
        .toList(growable: false);
  }

  List<String> get _workspaceFilters {
    final workspaces =
        _notes.map((note) => note.workspace).toSet().toList(growable: false)
          ..sort();
    return [_allWorkspacesLabel, ...workspaces];
  }

  List<String> get _notebookFilters {
    if (_selectedWorkspaceFilter == _allWorkspacesLabel) {
      return const [_allNotebooksLabel];
    }
    final notebooks =
        _notes
            .where((note) => note.workspace == _selectedWorkspaceFilter)
            .map((note) => note.notebook)
            .toSet()
            .toList(growable: false)
          ..sort();
    return [_allNotebooksLabel, ...notebooks];
  }

  List<NotebookNote> get _filteredNotes {
    return _notes
        .where((note) {
          if (_selectedWorkspaceFilter != _allWorkspacesLabel &&
              note.workspace != _selectedWorkspaceFilter) {
            return false;
          }
          if (_selectedNotebookFilter != _allNotebooksLabel &&
              note.notebook != _selectedNotebookFilter) {
            return false;
          }
          if (_searchQuery.isEmpty) {
            return true;
          }
          final haystack = [
            note.title,
            note.workspace,
            note.notebook,
            note.category,
            note.rawContent,
          ].join(' ').toLowerCase();
          return haystack.contains(_searchQuery);
        })
        .toList(growable: false);
  }

  List<_NotebookRailGroup> get _filteredRailGroups {
    final grouped = <String, List<NotebookNote>>{};
    for (final note in _filteredNotes) {
      final label = _selectedWorkspaceFilter == _allWorkspacesLabel
          ? '${note.workspace} / ${note.notebook}'
          : note.notebook;
      grouped.putIfAbsent(label, () => []).add(note);
    }

    return grouped.entries
        .map(
          (entry) => _NotebookRailGroup(label: entry.key, notes: entry.value),
        )
        .toList(growable: false);
  }

  String _noteScopeLabel(NotebookNote note) {
    if (_selectedWorkspaceFilter == _allWorkspacesLabel) {
      return '${note.workspace} / ${note.notebook}';
    }
    return note.notebook;
  }

  IconData _iconForChange(ChangeType type) {
    switch (type) {
      case ChangeType.spelling:
        return Icons.spellcheck;
      case ChangeType.formatting:
        return Icons.view_agenda_outlined;
      case ChangeType.clarity:
        return Icons.auto_fix_high_outlined;
      case ChangeType.verification:
        return Icons.fact_check_outlined;
    }
  }

  String _relativeDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes.clamp(1, 59)} min ago';
    }
    if (difference.inHours < 24) {
      return '${difference.inHours} hr ago';
    }
    return '${difference.inDays} d ago';
  }

  String _versionLabel(NotebookVersion version) {
    final mode = version.modelMode == ModelMode.localFast ? 'Local' : 'Cloud';
    return '$mode ${_relativeDate(version.createdAt)}';
  }

  double _compactNotesRailHeight(double availableHeight) {
    return (availableHeight * 0.24).clamp(180.0, 300.0);
  }

  String? get _snapshotSuggestedTitle {
    final value = _snapshot.artifacts
        .where((artifact) => artifact.kind == ArtifactKind.title)
        .map((artifact) => artifact.value.trim())
        .firstOrNull;
    if (value != null && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  List<String> get _snapshotActionItems {
    final artifactValue = _snapshot.artifacts
        .where((artifact) => artifact.kind == ArtifactKind.actionItems)
        .map((artifact) => artifact.value)
        .firstOrNull;
    if (artifactValue == null || artifactValue.trim().isEmpty) {
      return const [];
    }

    return artifactValue
        .split('\n')
        .map(_normalizeActionItemText)
        .whereType<String>()
        .toList(growable: false);
  }

  String? _normalizeActionItemText(String item) {
    final trimmed = item.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final cleaned = trimmed
        .replaceFirst(RegExp(r'^- \[[ xX]\]\s*'), '')
        .replaceFirst(RegExp(r'^-\s*'), '')
        .trim();
    if (cleaned.isEmpty) {
      return null;
    }
    return cleaned;
  }

  TextStyle? _editorTextStyle(ThemeData theme) {
    return theme.textTheme.bodyLarge?.copyWith(
      height: 1.45,
      fontSize: _editorAppearance.fontSize,
      fontWeight: _editorAppearance.isBold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: _editorAppearance.isItalic
          ? FontStyle.italic
          : FontStyle.normal,
      color: _editorAppearance.textColor,
      fontFamily: _fontFamilyName(_editorAppearance.fontFamily),
      fontFamilyFallback: _fontFamilyFallback(_editorAppearance.fontFamily),
    );
  }

  String _fontFamilyLabel(EditorFontFamily family) {
    return switch (family) {
      EditorFontFamily.modern => 'Modern',
      EditorFontFamily.editorial => 'Serif',
      EditorFontFamily.mono => 'Mono',
    };
  }

  String? _fontFamilyName(EditorFontFamily family) {
    return switch (family) {
      EditorFontFamily.modern => null,
      EditorFontFamily.editorial => 'Times New Roman',
      EditorFontFamily.mono => 'Courier New',
    };
  }

  List<String>? _fontFamilyFallback(EditorFontFamily family) {
    return switch (family) {
      EditorFontFamily.modern => null,
      EditorFontFamily.editorial => const ['Georgia', 'Times'],
      EditorFontFamily.mono => const ['Menlo', 'Monaco'],
    };
  }

  void _insertSnippet(String snippet) {
    final selection = _controller.selection;
    final originalText = _controller.text;
    final start = selection.isValid ? selection.start : originalText.length;
    final end = selection.isValid ? selection.end : originalText.length;
    final insertionPoint = start < 0 ? originalText.length : start;
    final replacementEnd = end < 0 ? originalText.length : end;
    final updatedText = originalText.replaceRange(
      insertionPoint,
      replacementEnd,
      snippet,
    );
    final caretOffset = insertionPoint + snippet.length;

    _applyRawEditorUpdate(updatedText, caretOffset: caretOffset);
  }

  void _insertMathBlock() {
    final insertion = _buildRawEditorInsertion(
      (originalText, start, end) => _authoringDirectiveService.insertMathBlock(
        originalText: originalText,
        selectionStart: start,
        selectionEnd: end,
      ),
    );

    _controller.value = _controller.value.copyWith(
      text: insertion.text,
      selection: TextSelection.collapsed(offset: insertion.selectionOffset),
      composing: TextRange.empty,
    );
    _editorFocusNode.requestFocus();
    _queueEnhancement(insertion.text);
  }

  void _insertTableBlock() {
    final insertion = _buildRawEditorInsertion(
      (originalText, start, end) => _authoringDirectiveService.insertTableBlock(
        originalText: originalText,
        selectionStart: start,
        selectionEnd: end,
      ),
    );

    _controller.value = _controller.value.copyWith(
      text: insertion.text,
      selection: TextSelection.collapsed(offset: insertion.selectionOffset),
      composing: TextRange.empty,
    );
    _editorFocusNode.requestFocus();
    _queueEnhancement(insertion.text);
  }

  ShortcutExpansionResult _buildRawEditorInsertion(
    ShortcutExpansionResult Function(String originalText, int start, int end)
    builder,
  ) {
    final selection = _controller.selection;
    final originalText = _controller.text;
    final start = selection.isValid ? selection.start : originalText.length;
    final end = selection.isValid ? selection.end : originalText.length;
    return builder(originalText, start, end);
  }

  bool _canApplyAiResult(AiCommandResult result) {
    return result.status == AiCommandStatus.completed &&
        result.content.trim().isNotEmpty;
  }

  void _insertAiResultAtCursor(AiCommandResult result) {
    final insertion = _formattedAiResult(result);
    if (insertion.isEmpty) {
      return;
    }
    _insertSnippet(insertion);
  }

  void _appendAiResultBelow(AiCommandResult result) {
    final insertion = _formattedAiResult(result);
    if (insertion.isEmpty) {
      return;
    }

    final originalText = _controller.text;
    final separator = originalText.trim().isEmpty
        ? ''
        : (originalText.endsWith('\n\n') ? '' : '\n\n');
    final updatedText = '$originalText$separator$insertion';
    _applyRawEditorUpdate(updatedText, caretOffset: updatedText.length);
  }

  Future<void> _restoreVersionRaw(NotebookVersion version) async {
    if (_controller.text != version.rawContent) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Restore raw snapshot'),
            content: const Text(
              'This will replace the current raw editor content with the selected snapshot.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Restore'),
              ),
            ],
          );
        },
      );
      if (confirmed != true) {
        return;
      }
    }

    _cancelPendingNoteWork();
    _applyRawEditorUpdate(
      version.rawContent,
      caretOffset: version.rawContent.length,
    );
  }

  void _insertVersionEnhancedAtCursor(NotebookVersion version) {
    final content = version.enhancedContent.trim();
    if (content.isEmpty) {
      return;
    }
    _insertSnippet(content);
  }

  void _appendVersionEnhancedBelow(NotebookVersion version) {
    final content = version.enhancedContent.trim();
    if (content.isEmpty) {
      return;
    }

    _cancelPendingNoteWork();
    final originalText = _controller.text;
    final separator = originalText.trim().isEmpty
        ? ''
        : (originalText.endsWith('\n\n') ? '' : '\n\n');
    final updatedText = '$originalText$separator$content';
    _applyRawEditorUpdate(updatedText, caretOffset: updatedText.length);
  }

  String _formattedAiResult(AiCommandResult result) {
    final content = result.content.trim();
    if (content.isEmpty) {
      return '';
    }
    return '${result.title}\n$content';
  }

  void _applyRawEditorUpdate(String updatedText, {required int caretOffset}) {
    _controller.value = _controller.value.copyWith(
      text: updatedText,
      selection: TextSelection.collapsed(offset: caretOffset),
      composing: TextRange.empty,
    );
    _editorFocusNode.requestFocus();
    _queueEnhancement(updatedText);
  }

  Future<void> _runEnhancement(String rawContent) async {
    if (!mounted) {
      return;
    }

    final selectedNoteId = _selectedNote?.id;
    final requestRevision = ++_enhancementRevision;
    final strippedContent = _aiCommandService.stripCommandLines(rawContent);

    setState(() {
      _isProcessing = true;
    });

    final snapshot = await widget.engine.process(
      EnhancementRequest(
        rawContent: strippedContent,
        modelMode: _mode,
        toggles: _toggles,
        revisionId: requestRevision,
      ),
    );

    if (!mounted) {
      return;
    }

    final isStale =
        requestRevision != _enhancementRevision ||
        selectedNoteId != _selectedNote?.id ||
        rawContent != _controller.text;
    if (isStale) {
      return;
    }

    setState(() {
      _snapshot = snapshot;
      _isProcessing = false;
    });
  }

  List<AiCommandResult> get _visibleAiCommandResults {
    final results = _aiCommandResults.values.toList(growable: false);
    results.sort(
      (left, right) =>
          left.request.lineIndex.compareTo(right.request.lineIndex),
    );
    return results;
  }

  String _providerLabelForMode(ModelMode mode) {
    return switch (mode) {
      ModelMode.localFast => 'Local AI request',
      ModelMode.cloudAccurate => 'Cloud AI request',
    };
  }

  String _compactPreview(String value) {
    final normalized = value
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.length <= 160) {
      return normalized;
    }
    return '${normalized.substring(0, 157)}...';
  }

  Future<void> _openAiDrawer([String? commandId]) async {
    if (!mounted) {
      return;
    }

    final available = _visibleAiCommandResults;
    final focusId = commandId ?? _activeAiCommandId;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final results = _reorderAiResults(available, focusId);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: FractionallySizedBox(
              heightFactor: 0.82,
              child: _buildAiDrawerContent(context, results),
            ),
          ),
        );
      },
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _activeAiCommandId = focusId;
    });
  }

  List<AiCommandResult> _reorderAiResults(
    List<AiCommandResult> results,
    String? focusId,
  ) {
    if (focusId == null) {
      return results;
    }
    final focused = results.where((result) => result.request.id == focusId);
    final remainder = results.where((result) => result.request.id != focusId);
    return [...focused, ...remainder];
  }

  Widget _buildAiDrawerContent(
    BuildContext context,
    List<AiCommandResult> results,
  ) {
    final theme = Theme.of(context);
    if (results.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AI Drawer',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Type commands like //explain, //explain formula, //define entropy, or //fact check to run AI only when you want it.',
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
          ),
        ],
      );
    }

    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final result = results[index];
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFD8DBD7)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    result.title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  _buildAiCommandStatusChip(result),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                result.request.displayLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF5A666F),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                result.providerLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF64717A),
                ),
              ),
              const SizedBox(height: 14),
              SelectableText(
                result.content.trim().isEmpty ? result.detail : result.content,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
              ),
              if (_canApplyAiResult(result)) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.tonal(
                      onPressed: () => _insertAiResultAtCursor(result),
                      child: const Text('Insert at cursor'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => _appendAiResultBelow(result),
                      child: const Text('Append below'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _statusLabel(ProcessorState state) {
    if (_isProcessing && state == ProcessorState.completed) {
      return 'Running';
    }

    return switch (state) {
      ProcessorState.completed => 'Active',
      ProcessorState.skipped => 'Off',
      ProcessorState.unavailable => 'Fallback',
      ProcessorState.failed => 'Error',
    };
  }

  Future<void> _openSettingsDialog() async {
    final baseUrlController = TextEditingController(
      text: widget.settings.ollamaBaseUrl,
    );
    final modelController = TextEditingController(
      text: widget.settings.ollamaModel,
    );
    final openAiBaseUrlController = TextEditingController(
      text: widget.settings.openAiBaseUrl,
    );
    final openAiApiKeyController = TextEditingController(
      text: widget.settings.openAiApiKey,
    );
    final openAiPrimaryModelController = TextEditingController(
      text: widget.settings.openAiPrimaryModel,
    );
    final openAiFastModelController = TextEditingController(
      text: widget.settings.openAiFastModel,
    );

    final result = await showDialog<AppSettings>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('AI Model Settings'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Local model',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: baseUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Ollama Base URL',
                      hintText: 'http://127.0.0.1:11434',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: modelController,
                    decoration: const InputDecoration(
                      labelText: 'Model',
                      hintText: 'gemma4:e4b',
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Cloud model',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: openAiBaseUrlController,
                    decoration: const InputDecoration(
                      labelText: 'OpenAI Base URL',
                      hintText: 'https://api.openai.com/v1',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: openAiApiKeyController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'OpenAI API Key',
                      hintText: 'sk-...',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: openAiPrimaryModelController,
                    decoration: const InputDecoration(
                      labelText: 'Primary cloud model',
                      hintText: 'gpt-5.4',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: openAiFastModelController,
                    decoration: const InputDecoration(
                      labelText: 'Fallback / mini model',
                      hintText: 'gpt-5.4-mini',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Use local settings for offline commands, and cloud settings for higher-quality explicit AI requests when you are online.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(
                  AppSettings(
                    ollamaBaseUrl: baseUrlController.text.trim().isEmpty
                        ? AppSettings.defaults.ollamaBaseUrl
                        : baseUrlController.text.trim(),
                    ollamaModel: modelController.text.trim().isEmpty
                        ? AppSettings.defaults.ollamaModel
                        : modelController.text.trim(),
                    openAiBaseUrl: openAiBaseUrlController.text.trim().isEmpty
                        ? AppSettings.defaults.openAiBaseUrl
                        : openAiBaseUrlController.text.trim(),
                    openAiApiKey: openAiApiKeyController.text.trim(),
                    openAiPrimaryModel:
                        openAiPrimaryModelController.text.trim().isEmpty
                        ? AppSettings.defaults.openAiPrimaryModel
                        : openAiPrimaryModelController.text.trim(),
                    openAiFastModel:
                        openAiFastModelController.text.trim().isEmpty
                        ? AppSettings.defaults.openAiFastModel
                        : openAiFastModelController.text.trim(),
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    baseUrlController.dispose();
    modelController.dispose();
    openAiBaseUrlController.dispose();
    openAiApiKeyController.dispose();
    openAiPrimaryModelController.dispose();
    openAiFastModelController.dispose();

    if (result == null) {
      return;
    }

    await widget.onSaveSettings(result);
    if (!mounted) {
      return;
    }
    await _refreshNoteProcessing(_controller.text);
  }
}
