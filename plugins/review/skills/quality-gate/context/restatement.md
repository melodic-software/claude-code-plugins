# Restatement review mode

A judgment lane over the **markdown files a branch changed**: does new prose duplicate content owned elsewhere, leak another surface's detail, or copy volatile external state? Reasoning only — no similarity thresholds, no mechanical gate.

## Scope

The changed `.md` files in the review diff base (SKILL.md "Shared inputs"), excluding generated files and changelogs. For each in-scope file, isolate the ADDED/CHANGED lines and judge those.

## The three lenses

1. **Restatement** — does the added prose recap content whose single source of truth lives elsewhere? Grep for candidate canonical homes (the heading, the concept, the value) across the project's docs and rules. When a canonical home exists, the fix is cite-by-reference rather than restating inline.
2. **Detail-leak** — does the added detail belong to a different surface? Detail that names another document's internals, options, or mechanics has leaked from the surface that owns that capability; it belongs there, cited from here.
3. **Recorded-external-state** — does the added prose copy externally-owned or derivable state (an issue/PR title or status, a hardcoded `file.ext:NNN` location, another repo's file list, a CI status snapshot, an inventory count) instead of storing a stable key and resolving it at read time?

When the project ships its own criteria for these concerns (SSOT/restatement review guides), read and apply those instead of the generic lenses — same precedence as all criteria in this skill.

## Scale guidance

- **Small diffs (≤15 markdown files)** — review inline, file by file.
- **Large diffs** — fan out per-batch read-only subagents (~40–50 files per batch, dispatched in small waves), each given the same three-lens method, then merge findings into one table.

## Artifact

Write a findings artifact to the findings location (SKILL.md "Shared inputs"), named `<UTC-timestamp>-restatement-review.md`, with frontmatter:

```yaml
---
type: restatement-review
mode: restatement
date: <ISO-8601 UTC>
branch: <branch>
reviewed_at_sha: <HEAD SHA>
diff_base: <merge-base SHA>
---
```

Findings table columns: `file:line | class | severity | finding | action`, where `class` is `restatement`, `detail-leak`, or `recorded-external-state`.

**A clean pass still writes the artifact** — scope (base SHA, HEAD SHA, file count) plus an explicit no-findings assertion. The artifact is evidence the lane ran, not just a record of what it found.
