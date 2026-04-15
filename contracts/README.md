# Smart Notebook Contracts

This folder contains the MVP data contracts for the smart notebook app.

## What is defined here

- `types.ts`: TypeScript interfaces for app code and service boundaries.
- `smart_notebook.contracts.schema.json`: JSON Schema bundle for validation and payload exchange.

## MVP assumptions

- Raw note content is never overwritten in place.
- Enhanced content is a derived artifact that can be regenerated.
- Change items are atomic, reviewable edits.
- Verification flags are advisory and should not silently rewrite facts.
- Enhancement runs are modeled as a pipeline request plus a pipeline result.

