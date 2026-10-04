# Code review mode

Specialized multi-aspect code feedback during development, before the formal PR gate.

## Boundary, the bundled `/code-review` skill

Claude Code ships `/code-review` as a [bundled skill](https://code.claude.com/docs/en/skills#bundled-skills) that reviews the same target this mode does: the branch's commits ahead of upstream plus uncommitted working-tree changes. It reports correctness bugs and reuse, simplification, and efficiency cleanups. It is always available (no plugin install), honors effort levels, and its `ultra` mode runs a deeper cloud review. Verified 2026-09-06 against Claude Code 2.1.263: the skills page lists `/code-review` among the bundled skills, and the code-review page documents the effort levels, where `low` and `medium` report only the highest-confidence findings while `high` through `max` broaden coverage, and states that `ultra` neither updates nor uses the remembered level. Recheck when the bundled-skill list drops it, when the effort behavior on that page changes, or when a release note names the command. Because it overlaps this mode on the "code review" trigger and the current diff, choose deliberately:

- **This mode** when the review must ground in the project's own standards and severity vocabulary (resolved through the standards index), stay report-only, and land in the gate's unified findings report. It dispatches the convention-aware reviewers in the paths below. (This is one lens per invocation; for a breadth fan-out across many review surfaces, reach for this plugin's `fanout` skill.)
- **`/code-review`** for a fast zero-dependency pass, or its `ultra` cloud deep-dive, when project-standards grounding is not the point. It does not read `REVIEW.md`, and its `--fix` / `--comment` flags mutate the working tree or PR, outside this mode's report-only contract, so reach for those only on explicit user opt-in (the sibling `pr` mode gates the same side effect).

## Size crossings (when code-metrics is enabled)

Before either path below, when `/code-metrics:audit-size` is among the available skills, run it
over the changed files with `--base <base>`, the review diff base, so both counts share one base.
Read the `file_lines` row of its References table (config key `size.file_lines`):

- **Layer `bundled default`:** pass nothing. The plugin's own reference is not the consumer's
  choice, so no file is flagged for size.
- **Any other layer** (`user-global`, `team`, `local`): the consumer set the value. For each
  changed file the report measured, count its non-blank lines (lines holding a non-whitespace
  character) at the review diff base with `git show`. Paths come from the diff and are untrusted:
  never type one into a command. Write the measured paths one per line to a file with the Write
  tool, then read them in a loop (`while IFS= read -r p; do git show "$base:$p"; done < <file>`),
  so each path reaches git as one variable-expanded argument; a file absent at the base counts 0. A file whose base count is below the reference and
  whose head `lines_non_blank` is at or above it is a crossing.

Put each crossing into the `code-reviewer` brief as `<path>: <base count> -> <head count>,
size.file_lines <reference> (<layer>)`. With no crossing, or when code-metrics is not available,
the brief lists none. On the primary path, which dispatches no `code-reviewer`, list the crossings
in the gate's report in that same form.

## Primary path: `pr-review-toolkit` orchestrator plugin (when installed)

When the `pr-review-toolkit` plugin (from the `claude-plugins-official` marketplace) is available, invoke `/pr-review-toolkit:review-pr` via the Skill tool with aspects detected from the changed files:

| Condition | Aspect |
|-----------|--------|
| Always (any code changes) | `code errors` |
| Test files changed | `tests` |
| New types added (class, record, struct, interface, enum) | `types` |
| Comments added or modified | `comments` |

Reserve the full multi-agent run for large (≥500 LOC) or security-sensitive changes. `all` is expensive.

## Fallback: this plugin's `code-reviewer` agent

When `pr-review-toolkit` is absent, dispatch this plugin's `code-reviewer` agent inline instead. It covers the core quality/convention/design dimensions in a single pass; note in the report that orchestrator breadth (dedicated error-handling, type-design, test, and comment analyzers) was skipped.

## When to use

- After implementing a feature, wanting agent feedback on code quality
- When suspecting error-handling gaps, type-design issues, or test-coverage holes
- As informal review before the project's formal pre-PR gate

## After the review

1. **Triage findings**: agent review findings carry a real false-positive rate; verify each against the diff before acting
2. **Fix CRITICAL and IMPORTANT items**; consider SUGGESTION items
3. **Re-run `self` mode** after fixes for a quick completeness re-check
4. **Proceed to the project's build/test verification**
