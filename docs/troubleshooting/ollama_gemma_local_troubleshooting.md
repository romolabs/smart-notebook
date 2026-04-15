# Ollama + Gemma Local Troubleshooting

## Scope
Use this guide when Smart Notebook should run locally through Ollama and a Gemma-family model, but the app falls back, hangs, or returns empty output.

This doc focuses on:
- local Ollama startup
- Gemma model availability
- runtime verification of the HTTP API
- common failure modes that look like app bugs but are really local runtime issues

## Assumptions
- Ollama is installed on the same machine as Smart Notebook.
- Ollama is listening on `http://localhost:11434`.
- The local model you want to use is a Gemma-family model already available in Ollama, or one you can pull successfully.
- Smart Notebook should remain usable even when the local model is unhealthy.

## Fast Triage
If local mode is not working, check these in order:

1. Is the Ollama service running?
2. Does Ollama see the Gemma model?
3. Can the local HTTP API answer a simple request?
4. Does the model return text quickly enough for interactive use?
5. Is Smart Notebook pointing at the right local host and port?

## Start Here
Run these checks from a terminal.

```bash
ollama --version
ollama serve
```

In a second terminal:

```bash
curl http://localhost:11434/api/tags
ollama list
ollama ps
```

Expected results:
- `curl /api/tags` returns JSON, not a connection error.
- `ollama list` shows the Gemma model you want to use.
- `ollama ps` shows a running model when one is loaded.

## Gemma Model Check
If the model is missing, pull the exact Gemma tag you intend to use.

```bash
ollama pull <gemma-tag>
ollama run <gemma-tag>
```

Use the tag that matches what `ollama list` shows in your environment.

Signs the model is available:
- `ollama list` includes the Gemma model name.
- `ollama run <gemma-tag>` opens an interactive prompt without errors.
- `ollama ps` shows the model after it starts.

## Runtime Verification
The fastest way to verify the full local path is to send a tiny API request directly to Ollama.

```bash
curl http://localhost:11434/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "model": "<gemma-tag>",
    "messages": [
      {
        "role": "user",
        "content": "Reply with exactly: local model ok"
      }
    ],
    "stream": false
  }'
```

Pass criteria:
- HTTP returns successfully.
- The response contains a non-empty assistant message.
- The reply is fast enough to feel usable for note editing.

If you prefer the generate endpoint, use a plain prompt:

```bash
curl http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "<gemma-tag>",
    "prompt": "Reply with exactly: local model ok",
    "stream": false
  }'
```

## Smart Notebook Verification
After the model works directly, verify the app path.

Expected app behavior:
- the local processor chips should stop showing fallback status
- the enhanced pane should update from local output
- raw notes should still save even if the local response is slow
- the app should not require cloud access for a successful local run

If the app still falls back after the direct API test passes, the problem is usually one of these:
- wrong Ollama host or port in the app settings
- stale runtime state after changing models
- model routing still set to cloud-only
- the app is using a different local host than `localhost`

## Common Problems And Fixes

### `connection refused` or `could not connect`
Likely cause:
- Ollama is not running
- Ollama is running on a different port

Fix:
- start `ollama serve`
- confirm the service responds on `http://localhost:11434`

### Model is not listed
Likely cause:
- the Gemma model was never pulled
- the wrong tag name was used

Fix:
- run `ollama list`
- pull the exact model tag you want
- retry `ollama run <gemma-tag>`

### The API responds but the app still uses fallback
Likely cause:
- Smart Notebook is pointed at the wrong host
- the routing mode is still set to a cloud-only path
- the local adapter cannot parse the model response

Fix:
- recheck the app's local model settings
- verify the app uses `http://localhost:11434`
- confirm the model response is plain text and not malformed JSON

### Output is very slow
Likely cause:
- the model is too large for the machine
- the machine is low on memory
- another model is already using the runtime

Fix:
- use a smaller Gemma-family model
- stop other running models with `ollama ps` and the relevant stop command
- retry with a short prompt first

### Output is empty, truncated, or oddly formatted
Likely cause:
- the prompt is too long
- the model is under memory pressure
- the runtime returned a partial completion

Fix:
- test with a tiny prompt first
- reduce prompt size
- retry with a smaller model if needed

## Minimum Healthy State
Before trusting local mode, confirm all of these:
- `ollama serve` is running
- `curl http://localhost:11434/api/tags` returns JSON
- `ollama list` shows the Gemma model
- a direct `api/chat` or `api/generate` request returns a non-empty response
- Smart Notebook shows local mode instead of fallback

## Useful Command Sequence

```bash
ollama serve
ollama list
ollama ps
curl http://localhost:11434/api/tags
curl http://localhost:11434/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "model": "<gemma-tag>",
    "messages": [
      {
        "role": "user",
        "content": "Reply with exactly: local model ok"
      }
    ],
    "stream": false
  }'
```

## What Not To Do
- Do not assume the app is broken before verifying Ollama directly.
- Do not treat a successful model load as proof that the app routing is correct.
- Do not use cloud fallback as the first fix when the local path is expected to work.
- Do not skip the direct API smoke test if you need to know whether the runtime or the app is failing.
