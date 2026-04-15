# Prompt Templates

This folder contains implementation-ready prompt templates for Smart Notebook processors.

Files:
- `formatter.md`
- `verifier.md`

Design rules:
- Treat the raw note as the source of truth.
- Return machine-readable output that can be validated before rendering.
- Fail soft: the app should keep the raw note even if a processor returns partial output or errors.
