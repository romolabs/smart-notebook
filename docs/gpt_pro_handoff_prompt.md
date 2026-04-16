# GPT Pro Smart Notebook Handoff Prompt

You are acting as a senior AI product engineer and prompt/pipeline architect.

I’m building a Flutter desktop app called Smart Notebook. It has:
- a left pane with raw notes
- a right pane with AI-enhanced notes
- local model support through Ollama
- current experiments with Gemma models
- a trust-first requirement: raw notes must stay untouched, and the enhanced pane must never get worse than the raw note

I need your help redesigning the enhancement process so the AI becomes genuinely useful, reliable, and structurally faithful.

Current problems:
1. Small local models sometimes make formatting worse instead of better.
2. The verifier can hallucinate dramatic warnings from casual text.
3. The formatter sometimes collapses lists/structure into worse output.
4. We need a pipeline that is “AI-powered” without blindly trusting the model.
5. We want a strong local-first experience, but we can optionally use stronger cloud models later.

Current architecture:
- Flutter desktop app
- Local model adapter in `lib/services/ollama_local_model_adapter.dart`
- Enhancement orchestration in `lib/services/mock_enhancement_engine.dart`
- The app currently has deterministic fallback formatting plus model-based formatting
- We already started gating model output when it degrades structure
- In local mode, we recently switched verification back to conservative local rules because weak models were hallucinating too much

Files included with this prompt:
- `lib/services/mock_enhancement_engine.dart`
- `lib/services/ollama_local_model_adapter.dart`
- `lib/models/notebook_models.dart`
- `lib/features/workspace/notebook_workspace.dart`
- `README.md`
- `docs/prompts/formatter_processor_prompt.md`
- `docs/prompts/verifier_processor_prompt.md`
- `docs/remaining_gaps_roadmap.md`

What I want from you:
Design a better enhancement pipeline for this note-taking app.

Please give me:

1. A recommended architecture for the enhancement pipeline
I want a concrete step-by-step pipeline, for example:
- preprocessing
- structural parsing
- deterministic formatting
- AI refinement
- verification
- acceptance/rejection rules
- final merge
Explain what should be deterministic vs model-driven.

2. A local-first strategy
Assume local models may be weak or inconsistent.
Tell me how to use local models safely for:
- spelling
- formatting
- clarity
- title generation
- summaries
- action items
- verification hints

3. A model routing strategy
I want a recommendation for:
- what should use a small local model
- what should require a stronger local model
- what should be deferred to cloud GPT
- when to veto model output automatically

4. Acceptance criteria for model output
Give me explicit rules the app can use to decide whether AI output is acceptable.
Examples:
- preserve line structure
- preserve list count
- preserve headings
- avoid hallucinated entities
- avoid dramatic re-interpretation
- avoid false factual certainty

5. Prompting strategy
Give me better prompt designs for:
- formatter
- verifier
- summarizer
Make them optimized for reliability and structured output, not just raw intelligence.

6. A scoring/evaluation framework
I need a way to test whether the enhanced note is actually better.
Please propose measurable heuristics and evaluation dimensions.

7. An implementation plan
Give me a practical implementation plan for this exact kind of app:
- MVP-safe version
- next version
- ideal version

Important product constraints:
- Raw note must never be silently modified.
- The enhanced note should feel clearly better than the raw note.
- If the AI is weak, the system should degrade gracefully instead of pretending.
- Trust is more important than maximum AI freedom.
- I care more about product usefulness than “AI purity.”
- I want the result to feel obviously AI-powered, but with guardrails.

Important answer style:
- Be concrete, not generic.
- Do not just say “use RAG” or “use agents.”
- Give a system design I could actually implement.
- If you recommend multiple stages, define what each stage receives and returns.
- If you propose prompts, keep them practical.
- If you propose output schemas, show them.

At the end, give me:
- the best overall recommendation
- the best local-only recommendation
- the best hybrid local + cloud recommendation

Assume I want to turn your answer directly into code changes.
