# Structured AI Notebook Roadmap

## Vision

Smart Notebook should become a trust-first notebook where deterministic structure
and bounded AI work together instead of competing.

The final product has three layers:

1. Deterministic structured authoring
2. Bounded AI assistance
3. Retrieval-grounded note intelligence

The deterministic layer keeps the notebook predictable and safe. The AI layer
adds real value where interpretation, synthesis, and explanation matter. The
retrieval layer lets the notebook answer questions and surface related notes
without relying on exact word matches.

## Product Pillars

### 1. Structured Authoring

Raw notes remain the source of truth. The author should be able to express note
intent directly instead of forcing the parser or model to guess.

Planned authoring primitives:

- line directives such as `/h1`, `/bullet`, `/check`
- block directives such as `/math ... /end` and `/table ... /end`
- inline symbol shortcuts such as `/alpha`, `/beta`, `/sigma`, `/sum`
- toolbar shortcuts that insert directives and snippets

This layer must stay deterministic, local, and useful even when no model
runtime is available.

### 2. Bounded AI Assistance

AI should matter, but only where it is genuinely useful.

Planned AI responsibilities:

- bounded prose cleanup around protected blocks
- grounded sidecars: title, summary, action items
- formula and derivation explanation
- assumption extraction
- conservative verification and review hints
- semantic synthesis over note content

The model should never own the final note body directly. It only proposes
bounded edits or artifacts and the engine stays responsible for acceptance and
merge.

### 3. Retrieval-Grounded Intelligence

The notebook should eventually support:

- semantic lookup across all notes
- related note suggestions by concept, not exact wording
- ask-your-notes Q&A using only retrieved notebook content
- note citations and grounded answers

This is the strongest long-term AI feature for the project and the clearest
resume story.

## Architecture Direction

### Deterministic Layer

- parser owns structure and protected blocks
- route planner decides what is safe for local AI
- formatter produces the deterministic champion draft
- renderer maps block types to widgets
- commands and symbol shortcuts are handled without the model

### AI Layer

- model proposes bounded line edits or sidecar artifacts
- acceptance gate validates structure and evidence
- merger applies only accepted proposals
- fallback remains useful when no local model is available

### Retrieval Layer

- notes are chunked into structured passages
- embeddings and metadata are stored locally
- semantic retrieval feeds grounded answer generation
- answerer must cite note chunks and refuse unsupported answers

## Delivery Plan

### Phase 1. Command-Driven Authoring

Goal: make note structure explicit and deterministic.

Implementation order:

1. inline symbol shortcuts
2. `/math ... /end`
3. `/h1`, `/bullet`, `/check`
4. `/table ... /end`
5. toolbar insertion for directives

### Phase 2. Math and Table Rendering

Goal: stop showing protected math as raw text in the enhanced pane.

Implementation order:

1. parser emits math and table block metadata
2. enhanced pane renders math blocks with a dedicated widget
3. enhanced pane renders structured tables
4. raw pane remains plain text and directive-based

### Phase 3. Better Deterministic Fallback

Goal: make the app valuable even when the local model is unavailable.

Implementation order:

1. better summaries
2. stronger action item extraction
3. artifact-only help for protected notes
4. clearer execution and fallback messaging

### Phase 4. Reliable Local AI Runtime

Goal: make bounded local AI actually usable.

Implementation order:

1. harden Ollama probe and retry behavior
2. improve runtime diagnostics in the UI
3. validate route-aware bounded proposal generation
4. preserve deterministic safety when runtime fails

### Phase 5. AI Features That Matter

Goal: use AI for tasks worthy of a resume project.

Implementation order:

1. explain selected formula or derivation
2. summarize math-heavy notes without rewriting formulas
3. extract assumptions and unresolved questions
4. compare related notes or snapshots

### Phase 6. Semantic Retrieval and Ask-Your-Notes

Goal: add a strong grounded AI layer over the notebook corpus.

Implementation order:

1. semantic note search
2. concept lookup and related notes
3. retrieval-grounded notebook Q&A
4. citation-first answer presentation

## Immediate Next Slice

The next implementation slice should be small, visible, and deterministic:

1. add inline symbol shortcuts in the raw editor
2. add `/math ... /end` block support in the parser
3. render math blocks properly in the enhanced pane

That sequence makes math authoring feel real while still fitting the
trust-first architecture.

## Resume Story

The strongest final framing is:

"Built a trust-first AI notebook with deterministic structured authoring,
math-aware protected rendering, bounded local LLM proposals with acceptance
gates, semantic retrieval over personal notes, and retrieval-grounded Q&A with
citations."
