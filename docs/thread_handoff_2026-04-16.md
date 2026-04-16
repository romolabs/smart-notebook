# Smart Notebook Thread Handoff

Date: 2026-04-16

## Repo

- Path: `/Users/angelromo/Learning/smart_notebook`
- Branch: `main`
- Remote: `https://github.com/romolabs/smart-notebook.git`

## Why This Handoff Exists

This document is meant to make it easy to continue the project in a new thread without rebuilding context from scratch.

It captures:

- current product direction
- current code state
- unblocked next steps
- known problems
- the exact architectural decision we are now committing to

## Product Direction

Smart Notebook is a trust-first split-pane notebook:

- left pane = raw note, preserved
- right pane = enhanced note, but only when the system can improve it safely

The core promise is:

> The enhanced pane must never silently become worse than the raw note.

That means the model cannot directly own the enhanced pane anymore.

## Final Architecture Decision

We reviewed both a Claude Opus architecture response and a GPT Pro architecture response, then synthesized them into one direction.

The agreed direction is:

- deterministic code owns structure
- the model proposes bounded improvements
- the engine validates proposals
- the engine merges accepted changes
- additive artifacts like title, summary, and action items should live beside the note
- local verification should be conservative review hints, not freeform factual judgment

The key principle is:

> The enhanced pane should be engine-authored, not model-authored.

## Source-Of-Truth Planning Docs

Read these first in the next thread:

1. `docs/enhancement_pipeline_master_plan.md`
2. `docs/gpt_pro_handoff_prompt.md`

The master plan is the main implementation blueprint.

## Current Code State

The app is a Flutter desktop app with:

- split raw/enhanced editor UI
- SQLite-backed note persistence
- local model settings
- Ollama local adapter
- current local model default set back to `gemma4:e4b`

Recent important code changes already present locally in this handoff state:

- local model default switched back to `gemma4:e4b`
- Ollama probe cache made host/model-aware
- local runtime status messages improved
- formatter path now prefers deterministic baseline when model output degrades structure
- local verifier path was downgraded to conservative deterministic review hints
- macOS entitlements now include outbound network access for localhost/Ollama
- architecture master plan doc added
- GPT Pro handoff prompt doc added

## Known Product / Code Problems

These still need work:

1. The architecture is still transitional.
   The current engine still thinks too much in strings and not enough in parsed structure.

2. The formatter pipeline is not yet the real champion/challenger design.
   It has safety patches, but not the full parser + proposal + gate + deterministic merge architecture.

3. `notebook_workspace.dart` still needs stale async response protection.
   Older enhancement results can still theoretically overwrite newer text.

4. There is a known layout overflow bug in the stacked editor path.
   It was previously observed around `lib/features/workspace/notebook_workspace.dart:488`.

5. The verifier terminology in the UI is still stronger than the actual safe behavior we want long term.

6. The local model is wired, but the app still needs a more robust bounded-edit proposal contract before local AI can be trusted as a real formatter collaborator.

## What We Should Build Next

This is the recommended implementation order.

### Phase 1: Trust Foundation

Build first:

1. `NoteParser`
2. structural models (`LineKind`, `LineNode`, `BlockKind`, `BlockNode`, metrics)
3. deterministic structure-preserving formatter
4. acceptance gate
5. stale-response protection in the workspace
6. calmer local review-hint behavior

### Phase 2: Proposal-Based AI

Then build:

1. model returns bounded line or block proposals
2. engine validates each proposal independently
3. engine merges only accepted edits
4. title/summary/action items become sidecar artifacts, not direct note body rewrites

### Phase 3: Routing And Hybrid Path

Then build:

1. capability-based routing
2. local model for bounded edits and additive artifacts
3. cloud model later for harder synthesis and stronger verification
4. one shared acceptance layer above both local and cloud

### Phase 4: Evaluation Harness

Then build:

1. fixture-based regression set
2. structure-preservation assertions
3. protected-token assertions
4. readability/helpfulness checks
5. stability checks

## Immediate First Slice

If the next thread starts implementation immediately, the best first coding slice is:

1. add parser/domain types in `lib/models/notebook_models.dart`
2. add `lib/services/note_parser.dart`
3. add `lib/services/deterministic_formatter.dart`
4. add `lib/services/acceptance_gate.dart`
5. refactor `lib/services/mock_enhancement_engine.dart` into the new staged flow
6. add revision-based stale response protection in `lib/features/workspace/notebook_workspace.dart`

## Files With Important Current Context

- `lib/services/mock_enhancement_engine.dart`
- `lib/services/ollama_local_model_adapter.dart`
- `lib/models/notebook_models.dart`
- `lib/features/workspace/notebook_workspace.dart`
- `macos/Runner/DebugProfile.entitlements`
- `macos/Runner/Release.entitlements`
- `docs/enhancement_pipeline_master_plan.md`
- `docs/gpt_pro_handoff_prompt.md`

## Git / Publish Intent

The goal of this handoff is:

- commit all current local changes
- push them to GitHub
- make the next thread able to start from a clean published state

## Recommended Opening Prompt For The Next Thread

Use something close to this:

> Read `docs/enhancement_pipeline_master_plan.md` and `docs/thread_handoff_2026-04-16.md` first. Then continue phase 1 of the Smart Notebook trust-first architecture refactor. Start with the parser, deterministic formatter, acceptance gate, and stale-response protection. Preserve existing UI behavior unless needed for the new architecture.

## Bottom Line

The project is now at a fork:

- keep patching prompts and heuristics
- or do the proper trust-first architecture refactor

The correct path is the refactor.

That is the plan this handoff is preserving.
