import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/notebook_models.dart';
import '../../services/mock_enhancement_engine.dart';
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
  final _controller = TextEditingController();
  final _searchController = TextEditingController();
  final _notesRailScrollController = ScrollController();

  List<NotebookNote> _notes = const [];
  NotebookNote? _selectedNote;
  EnhancementSnapshot _snapshot = const EnhancementSnapshot(
    enhancedContent: 'Your enhanced note will appear here as you type.',
    summary:
        'Start writing in the raw pane to see structure, cleanup, and verification hints.',
    changes: [],
    flags: [],
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
  int _enhancementRevision = 0;

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
                              height: 360,
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
        });
        _persistCurrentVersion();
      },
    );

    final settingsButton = FilledButton.tonalIcon(
      onPressed: _openSettingsDialog,
      icon: const Icon(Icons.tune),
      label: const Text('Settings'),
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
                settingsButton,
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
        settingsButton,
      ],
    );
  }

  Widget _buildNotesRail(
    BuildContext context, {
    bool compact = false,
    required NotebookNote selected,
  }) {
    final theme = Theme.of(context);
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
                    'Notebook',
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
            const SizedBox(height: 18),
            Expanded(
              child: _filteredNotes.isEmpty
                  ? _buildEmptySearchState(theme.textTheme)
                  : Scrollbar(
                      controller: _notesRailScrollController,
                      thumbVisibility: !compact,
                      child: ListView.separated(
                        key: PageStorageKey<String>(
                          'notes-rail-${compact ? 'compact' : 'desktop'}',
                        ),
                        controller: _notesRailScrollController,
                        primary: false,
                        scrollDirection: compact
                            ? Axis.horizontal
                            : Axis.vertical,
                        itemCount: _filteredNotes.length,
                        separatorBuilder: (_, _) => SizedBox(
                          width: compact ? 10 : 0,
                          height: compact ? 0 : 10,
                        ),
                        itemBuilder: (context, index) {
                          final note = _filteredNotes[index];
                          final isSelected = note.id == selected.id;
                          return SizedBox(
                            width: compact ? 220 : null,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () => _selectNote(note),
                              child: Ink(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFF153D44)
                                      : const Color(0xFFF6F6F1),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFF153D44)
                                        : const Color(0xFFE2E4DE),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      note.category,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: isSelected
                                                ? Colors.white70
                                                : const Color(0xFF5B605F),
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      note.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: isSelected
                                                ? Colors.white
                                                : null,
                                          ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      _relativeDate(note.updatedAt),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: isSelected
                                                ? Colors.white70
                                                : const Color(0xFF7B817F),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
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
      return Column(
        children: [
          Expanded(child: _buildRawPane(context)),
          const SizedBox(height: 16),
          Expanded(child: _buildEnhancedPane(context, selected: selected)),
        ],
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
      child: Column(
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
          const SizedBox(height: 16),
          Expanded(
            child: TextField(
              controller: _controller,
              onChanged: _queueEnhancement,
              expands: true,
              minLines: null,
              maxLines: null,
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
            ),
          ),
        ],
      ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFE5F1EC),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Summary',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: const Color(0xFF1E4A43),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _snapshot.summary,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildProcessorStatusRow(context),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFD8DBD7)),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _snapshot.enhancedContent,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final stackCards = constraints.maxWidth < 700;
                  if (stackCards) {
                    return Column(
                      children: [
                        _buildChangesCard(context),
                        const SizedBox(height: 14),
                        _buildVerificationCard(context, selected: selected),
                        const SizedBox(height: 14),
                        _buildVersionHistoryCard(context, selected: selected),
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
            ),
          ),
        ],
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
                child: Row(
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
                                : version.rawContent.trim().split('\n').first,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
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
              'Try another title or category keyword.',
              textAlign: TextAlign.center,
              style: theme.bodyMedium?.copyWith(color: const Color(0xFF5B605F)),
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
      _isLoading = false;
    });
    if (selected != null) {
      unawaited(_runEnhancement(selected.rawContent));
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

  Future<void> _refreshEnhancement() async {
    final selected = _selectedNote;
    if (selected == null) {
      return;
    }
    await _runEnhancement(_controller.text);
    _persistCurrentVersion();
  }

  void _selectNote(NotebookNote note) {
    setState(() {
      _selectedNote = note;
      _controller.text = note.rawContent;
    });
    unawaited(_runEnhancement(note.rawContent));
  }

  void _updateToggles(ProcessorToggles toggles) {
    setState(() {
      _toggles = toggles;
    });
    unawaited(_runEnhancement(_controller.text));
    _persistCurrentVersion();
  }

  Future<void> _createNewNote() async {
    final now = DateTime.now();
    final title = 'Untitled note ${_notes.length + 1}';
    final newNote = NotebookNote(
      id: 'note-${now.microsecondsSinceEpoch}',
      title: title,
      category: 'General',
      createdAt: now,
      updatedAt: now,
      rawContent: '',
      versions: const [],
    );

    setState(() {
      _notes = [newNote, ..._notes];
      _selectedNote = newNote;
      _controller.clear();
    });
    unawaited(_runEnhancement(''));

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

  List<NotebookNote> get _filteredNotes {
    if (_searchQuery.isEmpty) {
      return _notes;
    }

    return _notes
        .where((note) {
          final haystack = [
            note.title,
            note.category,
            note.rawContent,
          ].join(' ').toLowerCase();
          return haystack.contains(_searchQuery);
        })
        .toList(growable: false);
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

    _controller.value = _controller.value.copyWith(
      text: updatedText,
      selection: TextSelection.collapsed(offset: caretOffset),
      composing: TextRange.empty,
    );
    _queueEnhancement(updatedText);
  }

  Future<void> _runEnhancement(String rawContent) async {
    if (!mounted) {
      return;
    }

    final selectedNoteId = _selectedNote?.id;
    final requestRevision = ++_enhancementRevision;

    setState(() {
      _isProcessing = true;
    });

    final snapshot = await widget.engine.process(
      EnhancementRequest(
        rawContent: rawContent,
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

    final result = await showDialog<AppSettings>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Local Model Settings'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                const SizedBox(height: 12),
                Text(
                  'Use this to point the desktop app at your local Ollama runtime and preferred model.',
                  style: Theme.of(context).textTheme.bodySmall,
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
                  AppSettings(
                    ollamaBaseUrl: baseUrlController.text.trim().isEmpty
                        ? AppSettings.defaults.ollamaBaseUrl
                        : baseUrlController.text.trim(),
                    ollamaModel: modelController.text.trim().isEmpty
                        ? AppSettings.defaults.ollamaModel
                        : modelController.text.trim(),
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

    if (result == null) {
      return;
    }

    await widget.onSaveSettings(result);
    if (!mounted) {
      return;
    }
    await _runEnhancement(_controller.text);
  }
}
