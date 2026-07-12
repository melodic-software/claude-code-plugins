# End-of-Session Wrap-up

When a task or conversation appears complete, proactively suggest these before the user leaves.
Don't wait to be asked — suggest as soon as primary work is done.

## Checklist

1. **PR lifecycle** — if code was modified and a PR is planned, run the pre-PR sequence
   (`context/pre-pr.md`) and open the PR; if one exists, check CI status and outstanding review
   comments before leaving

2. **Save-point** — if the work is unfinished, write a `/handoff` so a fresh session resumes
   without rediscovery

3. **Retrospective** — `/retro` for substantive sessions (full analysis), `/retro quick` when
   context is limited, `/retro codify` when a specific learning surfaced mid-session

## When to suggest each item

| Condition | Suggest |
|-----------|---------|
| Code modified, no PR exists | Pre-PR sequence, then create the PR |
| PR exists, CI running | Monitor CI before leaving |
| Work unfinished, session ending | `/handoff` |
| Any session with substantive work | `/retro` (full or quick based on context budget) |
| Session had errors or surprises | `/retro codify` (capture specific learnings immediately) |
