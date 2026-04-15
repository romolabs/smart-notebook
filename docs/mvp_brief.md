# Smart Notebook MVP Brief

## Product Goal
Build a dual-pane notebook where the left side is the user's raw notes and the right side is an AI-enhanced version that improves spelling, structure, and readability without replacing the original.

## MVP Scope
- Raw notes editor with autosave.
- Enhanced pane that updates from the raw text.
- Clear diff or change markers between raw and enhanced text.
- Local-first storage with an optional cloud model path.
- Version history so the raw note is always recoverable.
- Basic settings for model mode and processor toggles.

## Non-Goals For V1
- Collaboration and shared workspaces.
- Audio transcription.
- Full citation-backed fact checking.
- Multi-document retrieval or knowledge graph features.
- Multi-agent autonomy exposed directly to users.

## Proposed Architecture
- UI layer: split-pane editor, note list, change review, settings.
- App layer: note service, version service, orchestration layer, diff layer.
- AI layer: formatter, verifier, and optional summarizer processors.
- Storage: local SQLite as the source of truth for notes and versions.
- Model routing: local model for cheap transforms, cloud model for higher-quality passes.

## Runtime Flow
1. User edits raw notes.
2. The app debounces input and snapshots a version.
3. The orchestrator runs processors in sequence.
4. The enhanced pane renders the latest structured output.
5. Change metadata and flags are stored with the version.

## Key Product Rules
- Never silently overwrite the raw note.
- Keep factual claims conservative and visible as suggestions or warnings.
- Treat formatting as automatic, but treat verification as advisory.
- Make every AI transformation reversible.
