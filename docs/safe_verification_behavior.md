# Safe Verification Behavior

## Goal
Make verification useful without presenting the model as an authority.

## Core Rule
Verification is advisory only.

The verifier may:
- flag suspicious claims
- suggest a correction
- ask for a source
- lower confidence on uncertain claims

The verifier must not:
- silently overwrite the raw note
- claim certainty without evidence
- remove user content
- invent sources or citations

## Output Style
Use conservative status labels:
- `unverified`
- `needs_source`
- `likely_wrong`
- `resolved`

Use wording that signals uncertainty:
- "possible issue"
- "needs confirmation"
- "source recommended"
- "this claim may be wrong"

## UI Behavior
- Show flags beside the enhanced content, not in the raw pane.
- Keep flagged content visible so the user can judge it.
- Let users accept, dismiss, or ignore a flag.
- Preserve raw text even when the verifier suggests a correction.

## Confidence Guidance
- High confidence still means "best effort", not truth.
- Low confidence should trigger softer language and fewer automatic suggestions.
- If the model cannot justify a flag, prefer `unverified` over a stronger claim.

## Safety Fallback
- If the verifier is unsure, return no correction rather than a speculative one.
- If verification fails, keep the enhanced text from the formatter and mark the run partial.
- If a claim is high-stakes and unsupported, recommend manual review instead of automatic rewriting.
