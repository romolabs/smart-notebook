# Formatter And Verifier Prompt Strategy

## Goal
Keep the enhanced pane useful, readable, and trustworthy without turning the model into a silent rewriter.

## Formatter Prompt
Use the formatter for spelling, grammar, structure, and readability.

Prompt rules:
- Preserve the note's meaning, order, and intent.
- Reflow text into headings, bullets, and short paragraphs when it helps clarity.
- Prefer local edits over full rewrites unless the note is very rough.
- Do not invent facts, timestamps, names, or action items.
- Keep any uncertainty out of the formatted text and put it in change items if needed.

Preferred output:
- Clean enhanced text.
- `ChangeItem` entries labeled `spelling`, `formatting`, or `clarity`.
- A confidence score for each major change block.

## Verifier Prompt
Use the verifier to detect claims that need confirmation.

Prompt rules:
- Extract factual claims, not opinions or style issues.
- Flag dates, numbers, named entities, and strong assertions first.
- Use cautious language such as "possible issue" or "needs source".
- Never rewrite the raw note to "fix" a fact.
- Return verification flags even when no corrections are made.

Preferred output:
- `VerificationFlag` entries with `status`, `confidence`, and an optional `suggestedCorrection`.
- `ChangeItem` entries only when the verifier adds a visible annotation to the enhanced pane.

## Shared Prompt Guardrails
- Raw text is the source of truth.
- Enhanced text is derived and replaceable.
- Every change should be explainable by category.
- Fail soft: partial output is better than blocking the save.
