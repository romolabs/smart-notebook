# Smart Notebook Enhancement Pipeline Master Plan

## Purpose

This document is the working plan for rebuilding Smart Notebook's enhancement system into something that is:

- trust-first
- structurally faithful
- clearly AI-powered
- local-first by default
- safe when models are weak
- extensible to stronger local or cloud models later

This plan is meant to be implementation-oriented. It is not just a brainstorm. It is the blueprint we should follow while refactoring the current app.

---

## Product Direction

Smart Notebook is not "AI writes your notes for you."

It is:

- a split-pane notebook
- where the raw note is preserved exactly
- and the enhanced pane becomes better only when the system can improve it safely

The core trust promise is:

> The enhanced pane must never silently become worse than the raw note.

That promise matters more than "AI purity."

---

## What We Learned

The current app taught us several important things:

1. A weak local model can easily make the enhanced note worse.
2. Prompt tuning alone is not enough to fix this.
3. Deterministic fallback formatting can also make notes worse if it invents structure.
4. Verification is especially dangerous when a weak model is allowed to speculate.
5. The engine needs to own trust, not the model.

The architectural conclusion is:

> The model must stop directly owning the enhanced pane.

Instead:

- deterministic code should define the note structure
- the model should propose bounded improvements
- the engine should validate and merge only safe changes

---

## Final Architectural Principle

The enhanced pane should always be engine-authored, not model-authored.

That means:

- the raw note is the canonical source
- the engine creates the baseline enhanced note deterministically
- the model proposes edits or sidecar artifacts
- the engine accepts or rejects those proposals
- the final enhanced text is assembled by deterministic code

This is the central design decision behind the entire refactor.

---

## High-Level Architecture

The enhancement system should become a staged pipeline:

1. Normalize
2. Parse structure
3. Build deterministic champion draft
4. Route model tasks
5. Request model proposals
6. Validate proposals
7. Merge accepted proposals
8. Build sidecar artifacts
9. Build review hints
10. Assemble final snapshot

We should think of this as a champion/challenger system:

- champion = deterministic best safe version
- challenger = model proposal
- challenger only wins when it passes hard gates

---

## Stage-by-Stage Plan

## 1. Normalize

### Goal

Prepare the note for analysis without mutating the canonical raw text.

### Input

- raw note text

### Output

- `NormalizedNote`

### Responsibilities

- preserve the exact raw text
- create an analysis copy with normalized line endings
- trim trailing whitespace in analysis copy only
- collapse excessive blank lines in analysis copy only when useful for parsing
- attach a `revisionId` or `sourceHash`

### Notes

We must stop relying on `rawContent.trim()` as the main working value early in the pipeline because that destroys fidelity and makes future span mapping harder.

---

## 2. Parse Structure

### Goal

Turn the note into a structural representation that the rest of the system can reason about safely.

### Input

- `NormalizedNote`

### Output

- `NoteStructure`

### Required types

- `LineKind`
- `LineNode`
- `BlockKind`
- `BlockNode`
- `StructureMetrics`

### Suggested `LineKind`

- `blank`
- `paragraph`
- `bullet`
- `orderedItem`
- `checkbox`
- `heading`
- `keyValue`
- `quote`
- `code`
- `tableRow`
- `unknown`

### Suggested parser rules

- `^#{1,6}` -> `heading`
- `^[-*•]` -> `bullet`
- `^\d+[.)]` -> `orderedItem`
- `^- \[ \]` or `^- \[x\]` -> `checkbox`
- `^>` -> `quote`
- code fence blocks -> `code`
- `key: value` patterns -> `keyValue`
- empty lines -> `blank`
- everything else -> `paragraph`

### Why this matters

Our current pipeline thinks in strings. That is too weak.

A structure-aware system can tell:

- whether a list was collapsed
- whether headings were dropped
- whether block order changed
- whether a model invented new sections

String comparison alone cannot do this reliably.

---

## 3. Deterministic Champion Draft

### Goal

Create the safest trustworthy enhanced note without depending on the model at all.

### Input

- `NoteStructure`
- processor toggles

### Output

- `ChampionDraft`

### Responsibilities

- normalize spacing
- normalize bullet markers
- normalize ordered list punctuation
- normalize blank lines between blocks
- preserve existing headings
- preserve list counts and order
- preserve checkbox state
- preserve URLs, emails, file names, model names, versions, dates, numbers, and code-like tokens
- improve spelling only through closed deterministic rules or a user lexicon

### Must not do

- invent headings like `# Enhanced Note`
- inject sections like `## Core Thought`
- rewrite the note semantically
- change commitment level
- transform journal or freeform writing into an outline unless the parser is extremely confident

### Important correction to current app

The current fallback formatter is too opinionated. It sometimes makes good raw notes worse.

The deterministic champion must be boring, safe, and structure-preserving.

---

## 4. Model Routing

### Goal

Decide what the model is allowed to do for the current note.

### Input

- `NormalizedNote`
- `NoteStructure`
- `ChampionDraft`
- `ModelMode`
- processor toggles

### Output

- `RoutePlan`

### Core rule

Route by capability, not by one giant "formatter" call.

### Example capabilities

- line edits
- block edits
- title suggestion
- summary suggestion
- action-item extraction
- review-hint wording

### Local-first routing

Small local models should only be used for:

- short line edits
- local clarity improvements
- title suggestion
- short summary
- action-item normalization from explicit evidence

Small local models should not be used for:

- owning note structure
- freeform verification
- factual judgment
- aggressive whole-note rewriting

### Future stronger routing

Cloud or stronger local models can later be used for:

- long-note synthesis
- stronger summaries
- more capable block refinement
- higher-confidence review flows

---

## 5. Model Proposals

### Goal

Make the model return bounded proposals instead of full note ownership.

### Input

- `RoutePlan`
- note structure
- champion draft

### Output

- `ModelProposal`

### Required proposal categories

- `LineEditProposal`
- `ArtifactProposal`
- optionally `ReviewHintTextProposal`

### Core rule

The model should not return "the final enhanced note."

It should return things like:

- replace line `l7` with `X`
- propose title `Y`
- propose summary `Z`
- normalize action item wording with evidence

### Why

This gives the engine control.

If the model is weak:

- the structure still survives
- only a few edits get accepted
- the note does not get hijacked

---

## 6. Acceptance Gate

### Goal

Reject model output that violates trust.

### Input

- champion draft
- model proposal
- note structure

### Output

- `AcceptedProposal`
- `AcceptanceReport`

### This is the trust wall

All model output must pass hard rules before it touches the enhanced pane.

### Hard acceptance rules

- structure must be preserved
- line order must be preserved
- block order must be preserved
- heading count must not drop without explicit deterministic justification
- ordered list count must not change unexpectedly
- checkbox count and state must be preserved exactly
- protected tokens must be preserved
- no new entities, numbers, dates, URLs, or file paths may be introduced
- no certainty upgrades
- no dramatic reinterpretation
- no invented facts
- no invented tasks
- no invented owners or due dates

### Behavior

Accept per proposal item, not only all-or-nothing.

If the model proposes 5 edits and only 2 are safe:

- keep the 2 safe edits
- reject the other 3

### Current code issue to replace

The existing `_shouldUseModelFormatter()` is too weak.

We need a real acceptance system, not a light heuristic.

---

## 7. Deterministic Merge

### Goal

Assemble the final enhanced text deterministically.

### Input

- champion draft
- accepted proposals

### Output

- `FinalEnhancedNote`

### Core rule

The model does not write the final note directly.

The engine applies accepted edits into a locked structure and renders the result itself.

That is what makes the product trustworthy.

---

## 8. Sidecar Artifacts

### Goal

Make the app feel more AI-powered without allowing risky note rewrites.

### Artifact types

- suggested title
- summary
- action items

### Product rule

Artifacts should be additive and separate from the main enhanced note.

They should not silently merge into the note body by default.

### Acceptance rules

- title must reuse source nouns/topics
- summary must use only source information
- action items must be evidence-backed
- missing owners or dates must remain `null`, not guessed

### Why

This gives obvious AI value without compromising note fidelity.

---

## 9. Review Hints

### Goal

Provide useful review/fact-check style guidance without pretending the system knows the truth.

### Local-mode rule

In `Local Fast`, review hints should be deterministic and calm.

### Allowed local signals

- explicit dates
- deadlines
- large metrics
- source-like phrases such as:
  - according to
  - research says
  - study shows
- named entities
- internal contradictions

### Must not do locally

- declare something false
- invent high-severity warnings
- re-interpret opinions as claims
- dramatize casual text

### Product language

Use "review hints" or "check-worthy claims" semantics, not "fact checker says this is wrong."

---

## 10. Snapshot Assembly

### Goal

Return a single UI-ready object.

### Output

- `EnhancementSnapshot`

### It should include

- final enhanced text
- summary
- accepted changes
- review hints
- processor statuses
- acceptance report / veto reasons where useful
- possibly artifact metadata later

---

## Local-First Strategy

### Spelling

Use:

- deterministic typo rules
- local lexicon
- protected token rules

Only let the model help when:

- the candidate is narrow
- edit distance is small
- token is not protected

### Formatting

For now:

- deterministic first
- structure-preserving only

The local model may refine wording, but should not own the layout.

### Clarity

Use local AI only on safe lines or paragraphs.

Avoid model clarity edits on lines with:

- names
- dates
- numbers
- deadlines
- code
- URLs
- uncertain claims

### Title generation

Safe for local AI because it is additive.

Always show as a suggestion, never silently apply.

### Summaries

Safe if short and evidence-backed.

### Action items

Must be extractive or evidence-backed.

No invention.

### Verification hints

Local mode should remain deterministic until a stronger verification path exists.

---

## Model Routing Strategy

### Small local model

Use for:

- line edits
- title suggestion
- short summary
- action-item normalization from explicit evidence

Do not use for:

- full-note formatting ownership
- fact verification
- strong claim analysis
- dramatic warning generation

### Stronger local model

Potential future use for:

- block-level clarity
- stronger summaries
- safer action-item extraction

### Cloud GPT

Potential future use for:

- long-note synthesis
- stronger summaries
- block restructuring proposals
- higher-value review flows

Even in cloud mode:

- the model should still propose
- the engine should still validate and merge

---

## Acceptance Criteria

These are the minimum rules we should encode.

### Structural fidelity

- preserve line order
- preserve block order
- preserve heading count unless explicitly justified
- preserve ordered list count
- preserve checkbox count and state

### Token fidelity

- preserve protected tokens
- preserve model names, versions, file names, URLs, emails, code-like tokens

### Entity fidelity

- no new names
- no new dates
- no new numbers
- no new deadlines

### Meaning fidelity

- do not remove uncertainty
- do not upgrade uncertainty into certainty
- do not change intention or commitment level
- do not add drama

### Artifact fidelity

- titles must be source-faithful
- summaries must be source-faithful
- action items must have evidence

---

## Evaluation Framework

We need a real evaluation harness instead of guessing.

### Metrics

- faithfulness
- structure preservation
- readability gain
- helpfulness
- stability

### Hard failure checks

- hallucinated entities
- hallucinated numbers
- hallucinated dates
- structure collapse
- invented tasks
- invented warnings

### Test fixture set

We should build a regression corpus covering:

- already-clean structured notes
- messy meeting notes
- numbered task lists
- technical notes with versions/model names
- journal/freeform notes
- notes with dates and metrics
- code/log snippets
- intentionally ambiguous casual text

### Target location

- `test/enhancement_eval/`

---

## Phased Implementation Plan

## Phase 1: Trust Foundation

### Goal

Stop the system from making notes worse.

### Tasks

- create structural types
- build `NoteParser`
- replace unsafe fallback formatter
- remove generic heading invention
- remove unsafe deterministic clarity rewrites
- add stronger acceptance gate
- add revision-based stale response protection
- reduce local verification to deterministic review hints

### Success criteria

- structured notes remain structured
- local verifier stops inventing alarming claims
- stale async responses cannot overwrite fresh text

---

## Phase 2: Proposal-Based AI

### Goal

Keep AI value while preserving trust.

### Tasks

- replace whole-note formatter outputs with bounded proposals
- add line-level or paragraph-level proposal mode
- validate proposals individually
- add title/summary/action-item artifact generation
- render artifacts separately from enhanced body

### Success criteria

- local AI improves narrow parts of notes
- engine remains in charge of final enhanced text

---

## Phase 3: Smarter Routing

### Goal

Use the right intelligence for the right job.

### Tasks

- capability-based routing
- note complexity scoring
- risk scoring
- stronger local/cloud adapters under same interface
- retry-on-veto only later if useful

### Success criteria

- local handles safe fast-path tasks
- stronger paths are used only where justified

---

## Phase 4: Evaluation and Release Discipline

### Goal

Measure quality before each major change.

### Tasks

- build regression fixture set
- create scoring harness
- log acceptance/veto metrics
- track stability and structure preservation

### Success criteria

- we can measure whether the enhanced pane is actually better

---

## File-Level Refactor Plan

### Files to introduce

- `lib/services/note_parser.dart`
- `lib/services/deterministic_formatter.dart`
- `lib/services/acceptance_gate.dart`
- possibly `lib/services/artifact_builder.dart`

### Files to refactor heavily

- `lib/services/mock_enhancement_engine.dart`
- `lib/services/ollama_local_model_adapter.dart`
- `lib/models/notebook_models.dart`
- `lib/features/workspace/notebook_workspace.dart`

---

## Immediate Work Order

This is the order I recommend we actually code in:

1. Add structural note types to `notebook_models.dart`
2. Build `NoteParser`
3. Build deterministic formatter
4. Replace current fallback formatting
5. Add stronger formatter gate
6. Add stale-response protection in workspace
7. Simplify local verifier into deterministic hints only
8. Add title/summary sidecars
9. Refactor model adapter toward proposals later
10. Build evaluation fixtures

---

## What We Should Not Do Right Now

- continue trying to solve this only with prompt tuning
- let the model fully own the enhanced pane
- let local AI own verification
- add multi-agent complexity
- add RAG before trust is fixed
- overengineer embeddings-based gates too early

---

## Final Recommendation

The right move is:

> rebuild the enhancement pipeline around deterministic structure plus bounded AI proposals.

That gives us:

- a safer product
- a more trustworthy product
- a better local-first strategy
- a cleaner future cloud path
- and an app that still feels obviously AI-powered

The implementation should start with the trust foundation, not with more prompt experiments.

---

## Definition Of Success

We are successful when:

- raw notes remain untouched
- enhanced notes are consistently better than raw notes
- local AI can help without being dangerous
- weak models degrade gracefully
- verification becomes calm and useful
- the engine, not the model, owns trust

This is the plan we should use to start the refactor.
