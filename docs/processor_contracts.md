# Processor Contracts

## Shared Contract
Each processor receives raw note text plus lightweight note metadata and returns:
- transformed text or annotations
- a list of change items
- a confidence score when applicable
- a failure state that does not block note saving

## Formatter
Purpose:
- Reflow messy text into headings, bullets, and readable paragraphs.
- Normalize spacing, punctuation, and markdown-like structure.

Output rules:
- May rewrite aggressively for presentation.
- Must not invent new facts.
- Should preserve meaning and order unless a structure change is obvious.

## Spell And Grammar Editor
Purpose:
- Correct spelling, grammar, casing, and small wording mistakes.

Output rules:
- Keep edits local when possible.
- Prefer minimal textual changes over full rewrites.
- Emit precise change markers for accepted edits.

## Verifier
Purpose:
- Flag claims that may need confirmation.
- Highlight dates, numbers, named entities, and strong assertions.

Output rules:
- Do not silently change facts.
- Return warnings, confidence levels, and suggested verification notes.
- Prefer "possible issue" language over hard assertions.

## Summarizer
Purpose:
- Produce a compact note summary or top-level gist.

Output rules:
- Optional in MVP.
- Must derive only from the source note.
- Should be stored separately from the enhanced canonical text.

## Orchestrator
Responsibilities:
- Decide which processors to run for a given edit.
- Order processors so formatting and spelling happen before verification.
- Merge outputs into one enhanced view.
- Fall back cleanly when a processor fails or times out.

## Failure Handling
- Save the raw note even if AI processing fails.
- Show partial output when only some processors succeed.
- Surface processor errors as status badges, not app crashes.
