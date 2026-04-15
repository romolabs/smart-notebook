# Ollama Local Adapter For MVP

## Purpose
Define the local-model integration contract for the MVP so formatter and verifier processors can run through an Ollama-backed adapter without depending on app-specific UI code.

## Request Shape
The adapter should accept one normalized request object:

- `task`: `formatter` | `verifier` | `summarizer`
- `noteId`: stable note identifier
- `versionId`: optional snapshot identifier
- `rawText`: the source note content
- `noteMeta`: optional lightweight metadata such as title, note type, and processor toggles
- `mode`: expected routing mode, usually `local_fast`
- `constraints`: optional rules such as `preserveMeaning`, `preserveOrder`, and `advisoryOnly`

The adapter should return:

- `outputText`: transformed text when applicable
- `changeItems`: categorized edits or annotations
- `verificationFlags`: claim warnings when applicable
- `confidence`: optional overall confidence score
- `status`: `ok` | `partial` | `timeout` | `error`
- `errorMessage`: short human-readable failure note when needed

## Model Assumptions
For MVP, assume the local runtime:

- is hosted through Ollama on `localhost`
- serves one primary small-to-mid model that is reused across tasks
- is good at short, mechanical transformations
- may be weaker on deep fact checking than cloud routing
- should be treated as best-effort, not authoritative

The adapter should not require model-specific behavior beyond a plain text instruction prompt plus the source note payload.

## Timeout And Fallback
Local calls should fail soft.

- Use a short timeout for interactive typing paths so the enhanced pane stays responsive.
- If the local call times out, keep the raw note and the last successful enhancement.
- If local output is partial, surface it instead of blocking save.
- If the local adapter errors repeatedly, let the orchestrator fall back to cloud only when routing rules allow it.
- If both local and cloud fail, preserve raw content and show a processor status badge.

Recommended behavior:

- formatter timeout should prefer a partial textual result over no result
- verifier timeout should preserve any already-extracted warnings
- summarizer can be skipped entirely when time is tight

## Privacy Expectations
Local mode should be the default privacy-friendly path.

- Raw notes stay on-device unless the user explicitly routes to cloud.
- The adapter should send only the minimum text needed for the selected task.
- No silent background syncing of note contents.
- No training or retention assumptions should be made beyond the local Ollama runtime.
- Sensitive notes should remain usable even when cloud access is disabled.

## MVP Boundary
This adapter doc only covers the local execution contract.

- It does not define the UI.
- It does not define the database schema.
- It does not define the cloud provider contract.
- It does define the fallback expectation that local failure must not block note saving.
