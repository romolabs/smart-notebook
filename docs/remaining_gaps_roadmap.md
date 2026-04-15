# Smart Notebook Remaining Gaps Roadmap

This doc lists the highest-priority gaps still remaining after the current MVP scaffold. The goal is to turn the app from a convincing prototype into a trustworthy, shippable product.

## P0: Must Close Next

### 1. Trust And Review Workflow
- Add a first-class review flow for enhanced output.
- Let users inspect changes by category and accept or reject them.
- Show verification warnings without pretending they are facts.
- Preserve raw text and keep every enhancement reversible.

### 2. Real Cloud Path
- Replace the `Cloud Accurate` placeholder with an actual provider integration.
- Route long, claim-heavy, or high-value notes to the cloud path.
- Keep fallback behavior when the provider is unavailable.
- Make model choice visible so users know what is local vs remote.

### 3. Note Management
- Improve note creation, renaming, deletion, and search.
- Add lightweight organization such as tags or note types.
- Make the notes rail feel like a real library instead of a sample list.
- Add empty states and clearer navigation for multi-note use.

### 4. Version Restore
- Add explicit restore from historical snapshots.
- Let users compare current state with prior versions.
- Keep version history easy to scan instead of buried in metadata.
- Make restore safe enough that users can recover from bad edits quickly.

## P1: Should Close Soon

### 5. Settings And Model Control
- Add a proper settings screen for Ollama host, local model, and cloud provider settings.
- Expose processor toggles in a clear place instead of only in the main workspace.
- Store privacy and routing preferences persistently.
- Make defaults obvious for first-run setup.

### 6. Test Coverage
- Add more widget tests for the split-pane workspace.
- Add repository tests for SQLite persistence and migrations.
- Add service tests for routing and fallback behavior.
- Add at least one regression test for version restore.

### 7. Error Handling And Observability
- Surface model, storage, and migration failures in a human-readable way.
- Add minimal logging around enhancement runs and save failures.
- Distinguish between fallback behavior and true errors.
- Make startup failures diagnosable without opening the code.

## P2: Later

### 8. Cloud-Safe Collaboration And Sync
- Add sync metadata only after the local data model is stable.
- Support export/import before full multi-device sync.
- Avoid turning the first release into a collaboration product too early.

### 9. Deep AI Features
- Add summaries, action items, and study-note transforms after the core review loop is solid.
- Consider specialized processors only when the pipeline feels stable.
- Avoid expanding the agent surface until trust and restore are working well.

## Build Order Recommendation
1. Trust and review.
2. Cloud path.
3. Note management and version restore.
4. Settings and tests.
5. Observability.
6. Sync and deeper AI features.

## Why This Order
- Trust features protect the product promise first.
- Cloud routing unlocks the premium path without blocking local use.
- Note management and restore make the app usable as a real notebook.
- Settings and tests reduce friction and regression risk.
- Sync and extra AI features are valuable, but they depend on the foundation above.
