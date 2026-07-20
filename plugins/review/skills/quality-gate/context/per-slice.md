# Per-slice review mode

Dispatches a general subagent to review changed files against ONE named per-concern criteria document from the consuming project (e.g. testing, logging, concurrency, performance, error-handling, cross-platform).

## Locating the slice

When `slice <name>` is selected:

1. Find the project's criteria document for `<name>` — common shapes: `review/<name>.md`, `review/<name>/README.md`, `docs/review/<name>.md`. Glob before dispatching; if no criteria document exists for `<name>`, say so and list the criteria documents that DO exist (or suggest `criteria` mode when the project has none).
2. Spawn a general read-only subagent with this prompt template:

```text
You are a specialist reviewer for <SLICE-NAME> concerns.

Read in order:
1. The project's severity vocabulary (its review hub doc when present).
2. <path-to-slice-file> — your review criteria.
3. The change set: git diff <review-diff-base> (the dispatcher substitutes the
   resolved review diff base from SKILL.md "Shared inputs" — the PR's real base
   when one exists, else the origin/HEAD -> remote default branch -> origin/main -> HEAD fallback),
   plus git ls-files --others --exclude-standard (Read any untracked files it lists).
   Bare `git diff HEAD` alone is empty on a clean committed branch.

Review every changed file against ONLY that slice's criteria.

Report findings in this format:

## Review: <slice-name> — <branch>

### Findings

| # | Severity | Finding | File:Line | Action |
|---|----------|---------|-----------|--------|

### Summary
- CRITICAL / IMPORTANT / SUGGESTION counts

If zero findings, report "No <slice-name> issues found in changed files."
```

1. Verify the subagent's findings against the diff, then present them.

## When a dedicated agent exists

For concerns this plugin ships a dedicated agent for (code quality → `code-reviewer`, security → `security-reviewer`, architecture → `architecture-guardian`), prefer the dedicated agent — it adds persistent memory across sessions. Slice mode still works for those concerns when the user names them explicitly.
