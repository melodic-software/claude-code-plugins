# Code review mode

Specialized multi-aspect code feedback during development, before the formal PR gate.

## Boundary — the built-in `/code-review` skill

Claude Code ships a built-in `/code-review` bundled skill that reviews the same target this mode does — the branch's commits ahead of upstream plus uncommitted working-tree changes — for correctness bugs and reuse, simplification, and efficiency cleanups. It is always available (no plugin install), honors effort levels, and its `ultra` mode runs a deeper cloud review. Because it overlaps this mode on the "code review" trigger and the current diff, choose deliberately:

- **This mode** when the review must ground in the project's own standards and severity vocabulary (resolved through the standards index), stay report-only, and land in the gate's unified findings report. It dispatches convention-aware reviewers — the paths below. (This is one lens per invocation; for a breadth fan-out across many review surfaces, reach for this plugin's `fanout` skill.)
- **`/code-review`** for a fast zero-dependency pass, or its `ultra` cloud deep-dive, when project-standards grounding is not the point. It does not read `REVIEW.md`, and its `--fix` / `--comment` flags mutate the working tree or PR — outside this mode's report-only contract, so reach for those only on explicit user opt-in (the sibling `pr` mode gates the same side effect).

## Primary path — `pr-review-toolkit` orchestrator plugin (when installed)

When the `pr-review-toolkit` plugin (from the `claude-plugins-official` marketplace) is available, invoke `/pr-review-toolkit:review-pr` with aspects detected from the changed files:

| Condition | Aspect |
|-----------|--------|
| Always (any code changes) | `code errors` |
| Test files changed | `tests` |
| New types added (class, record, struct, interface, enum) | `types` |
| Comments added or modified | `comments` |

Reserve the full multi-agent run for large (≥500 LOC) or security-sensitive changes — `all` is expensive.

## Fallback — this plugin's `code-reviewer` agent

When `pr-review-toolkit` is absent, dispatch this plugin's `code-reviewer` agent inline instead. It covers the core quality/convention/design dimensions in a single pass; note in the report that orchestrator breadth (dedicated error-handling, type-design, test, and comment analyzers) was skipped.

## When to use

- After implementing a feature, wanting agent feedback on code quality
- When suspecting error-handling gaps, type-design issues, or test-coverage holes
- As informal review before the project's formal pre-PR gate

## After the review

1. **Triage findings** — agent review findings carry a real false-positive rate; verify each against the diff before acting
2. **Fix CRITICAL and IMPORTANT items**; consider SUGGESTION items
3. **Re-run `self` mode** after fixes for a quick completeness re-check
4. **Proceed to the project's build/test verification**
