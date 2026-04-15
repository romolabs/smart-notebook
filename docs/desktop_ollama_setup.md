# Smart Notebook Desktop Ollama Setup

Use this when you want Smart Notebook on desktop to run the local formatter and verifier path through Ollama.

## Expected Endpoint

- Ollama should be available at `http://localhost:11434`
- The app should be able to reach the local Ollama API on the default port
- Common API paths are `/api/chat` and `/api/generate`

## Install And Start Ollama

1. Install Ollama for your desktop platform from the official Ollama app/site.
2. Start the local service if it is not already running:

```bash
ollama serve
```

## Example Models

Good MVP-friendly model names to try:

- `llama3.2`
- `qwen2.5`
- `mistral`
- `phi3.5`

## Pull And Run

You can either pull first, then run:

```bash
ollama pull llama3.2
ollama run llama3.2
```

Or just run the model and let Ollama fetch it on demand:

```bash
ollama run qwen2.5
```

If you want a smaller, faster local path for short edits, `llama3.2` is a good first choice. If you want to test a second option, `qwen2.5` is also a good candidate.

## What Smart Notebook Shows When Ollama Is Missing

If the local runtime is not available, the app should stay usable and fall back safely.

- The processor chips show `Formatter: Fallback` and `Verifier: Fallback`
- Hover text says `No local model runtime detected.`
- Raw notes still save normally
- The enhanced pane uses fallback behavior instead of blocking the note

## Quick Check

If you want to confirm Ollama is up before opening the app, make sure the local server responds on `localhost:11434` and that `ollama ps` shows a running model.
