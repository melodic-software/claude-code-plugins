# Code review mode

Specialized multi-aspect code feedback during development, before the formal PR gate.

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
