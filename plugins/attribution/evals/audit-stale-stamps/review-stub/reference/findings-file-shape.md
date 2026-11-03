# Findings-file contract (eval stand-in)

Write the report to the findings location (`skills/fanout/SKILL.md`, "Shared inputs") as
`<UTC timestamp>-<topic>.md`, with the timestamp from `date -u +%Y%m%dT%H%M%SZ`. Never overwrite an
existing path: add `-2`, the smallest free integer. Cite `file:line` repo-relative only.

```markdown
---
type: review-findings
date: <ISO-8601 UTC, the instant the file is written>
branch: <branch>
---

## Findings

| Rank | Tier | Confidence | Location | Surface(s) | Finding | Action |
|------|------|------------|----------|------------|---------|--------|

## Unparsed

## Surfaces

Ran: [...]. Returned no result: [...].
```

In `Finding` and `Action` cells, escape `|` as `\|` and replace newlines with spaces.
