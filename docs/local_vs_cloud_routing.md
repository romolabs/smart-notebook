# Local Vs Cloud Routing Heuristics

## Goal
Route easy, private, and low-risk transformations locally, and reserve cloud calls for harder or higher-stakes passes.

## Default Routing
Use `local_fast` when the task is mostly structural or cosmetic:
- spelling and grammar cleanup
- formatting into headings and bullets
- lightweight clarity improvements
- short notes with low ambiguity

Use `cloud_accurate` when the task benefits from more reasoning or broader context:
- long notes with many claims
- research or technical notes
- verification-sensitive content
- notes with dense entities, dates, or numbers
- user requests to "fact check" or "be careful"

## Heuristics
Prefer local routing when:
- the note is short
- the note is private or sensitive
- the user is offline or has cloud disabled
- the change is mostly mechanical
- there are no obvious factual claims to assess

Prefer cloud routing when:
- the note contains many claims that could be wrong
- the note is a meeting recap with action items and dates
- the note is a class or research note with terminology that may need polishing
- the local pass returns low confidence or weak structure
- the user explicitly asks for a higher quality pass

## Escalation Rules
- Run local first, then escalate only the uncertain or high-value portions.
- Keep the enhanced pane responsive by avoiding unnecessary cloud calls.
- Route verification to cloud only when the claim density or risk justifies it.
- Never route just to "make it sound smarter" if local output is already adequate.

## Fallback Behavior
- If cloud fails, keep the local result.
- If local fails, preserve the raw note and show a processor status badge.
- If routing is unclear, default to local and surface a "review needed" warning.
