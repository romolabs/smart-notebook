# Smart Notebook

Smart Notebook is a Flutter desktop app for writing messy notes on the left and seeing a cleaner, AI-enhanced version on the right. The raw note stays intact, while the enhanced pane focuses on spelling, formatting, clarity, and cautious verification hints.

## What The App Is

This project is a trust-first notes workspace built around a split view:

- `Raw` is the source of truth.
- `Enhanced` is the AI-assisted version.
- Changes are explainable and reversible.
- Local storage keeps notes and version history on disk.

The current app is a desktop-first Flutter build with local SQLite storage, seeded sample notes, and a local model adapter that can use Ollama when it is available.

## Current MVP Capabilities

The app currently supports:

- A split-pane editor with raw and enhanced content side by side.
- A notes rail for switching between saved notes.
- Live enhancement updates while you type.
- Processor toggles for spelling, formatting, clarity, and verification.
- A model mode switch between `Local Fast` and `Cloud Accurate`.
- Version history for recent note snapshots.
- SQLite-backed persistence under `.smart_notebook/smart_notebook.db`.
- Safe fallback behavior when Ollama is not available.

What is still limited:

- `Cloud Accurate` is a UI/routing path, but cloud providers are not wired in yet.
- Local enhancement is best-effort and may fall back to deterministic behavior if Ollama is missing or unreachable.

## Ollama And Gemma 4

The desktop app is currently configured to look for Ollama on `http://127.0.0.1:11434` and uses `gemma4:e4b` as the default local model.

If you are setting up a local model for the first time, this is the expected flow:

1. Install Ollama for your desktop platform.
2. Start the Ollama service:

```bash
ollama serve
```

3. Pull and run the model the app expects:

```bash
ollama pull gemma4:e4b
ollama run gemma4:e4b
```

4. Confirm the local server is reachable:

```bash
curl http://127.0.0.1:11434/api/tags
```

If Ollama is not running, the app should still open and keep working. In that case, the processor chips will show fallback behavior and the enhanced pane will use local deterministic output instead of blocking the note.

## How To Run The Flutter App

From the project root:

```bash
flutter pub get
flutter run -d macos
```

If you want another desktop target, replace `macos` with `windows` or `linux` on a machine that supports it.

Useful checks:

```bash
flutter analyze
flutter test
```

## Project Shape

- `lib/` contains the app shell, workspace UI, models, repository, and enhancement pipeline.
- `docs/` contains the product, storage, prompt, and Ollama setup notes that define the MVP contract.
- `test/` contains the widget test for the desktop workspace.

## Notes

This repository is still early, but the product direction is already established: preserve the original note, improve the readable version beside it, and never silently rewrite facts.
