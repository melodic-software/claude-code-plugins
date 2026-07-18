# review

A Claude Code plugin bundling one cohesive capability: **code review**. Six read-only
reviewer agents plus two orchestration skills — a single-lens quality gate and a
multi-surface review fan-out that normalizes every reviewer's output into one
severity-ranked, deduplicated findings report.

## Components

### Agents (six, all read-only)

| Agent | Concern |
|---|---|
| `code-reviewer` | Quality, convention adherence, and design judgment automated tooling misses; carries a named Fowler design-smell baseline (advisory, project standards override) |
| `security-reviewer` | Cross-ecosystem security audit — OWASP Top 10, injection, secrets, auth (P1–P5 severity) |
| `architecture-guardian` | Dependency direction, boundary integrity, pattern compliance |
| `doc-drift-detector` | Documentation that no longer matches the code — stale, missing, aspirational |
| `ecosystem-specialist` | Multi-language build/test/lint verification, detected from changed paths |
| `ci-log-auditor` | GitHub Actions run audit — masked failures, skipped jobs, suspicious successes, perf outliers |

All six carry persistent per-project memory (`memory: local`, stored under
`.claude/agent-memory-local/` and never checked into version control) so they learn a
codebase's patterns across sessions without dirtying the consumer repo's tracked tree —
"read-only" means the reviewed code; agent memory is the one documented write path.
Invoke via `@review:<agent>` or let Claude delegate.

### Skills (two)

- **`/review:quality-gate [mode]`** — the single-lens checkpoint between "code works"
  and "code is ready". Modes: `self` (fresh-context self-review), `code`, `architecture`,
  `security`, `pr`, `criteria`, `slice <name>`, `restatement`.
- **`/review:fanout [mode]`** — breadth review: fans out across the
  reviewer agents, the project's own per-concern review criteria docs, and optional
  orchestrator review plugins, then normalizes everything into one ranked findings report.
  Modes: default (auto-scales to diff size), `run-everything` (full roster), `fix` (applies
  a persisted findings file — the only mutating mode).

## Works in any repo

- **Reads your conventions, assumes none.** Every agent and skill reads the consuming
  project's own review criteria, severity vocabulary, and conventions first (`CLAUDE.md`,
  project rules, `REVIEW.md`/review docs); the plugin's bundled baseline
  (`context/severity.md`) applies only where the project defines nothing.
- **Command truth from `.claude/ecosystems/`.** `ecosystem-specialist` resolves each
  ecosystem's build/test/lint command from the consumer's `.claude/ecosystems/<ecosystem>.yaml`
  files when present (the marketplace-wide ecosystem-commands contract,
  `docs/conventions/ecosystem-commands/README.md`), falling back to your documented conventions,
  then its own bundled generic defaults as a last resort.
- **Graceful degrade.** Optional orchestrator plugins (`pr-review-toolkit`, `code-review`
  from the official marketplace) add adversarial breadth when installed; every path works
  without them.
- **Self-contained.** The severity baseline and all mode guidance ship inside the plugin
  and are referenced via `${CLAUDE_PLUGIN_ROOT}`.

## Findings location

Review findings persist to the directory the `.claude/topic-docs.yaml` concern file's
`memory_dir` resolves (`<memory_dir>/reviews/<branch-slug>/`); else to a review-artifacts
location the project's own conventions declare; else to the default `.work/reviews/<branch-slug>/`
at the project root — the topic-docs convention's memory tier, concern-scoped on the branch axis
(`reference/topic-docs.md`). The memory root self-ignores (a `.gitignore` containing `*`,
created on the session's first memory-tier write), so findings never enter version control.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install review@melodic-software
```

## Configuration

No `userConfig`. Consumer customization routes through your own project context: review
criteria docs and severity vocabulary override the bundled baseline, and a documented
findings location in your `CLAUDE.md`/rules overrides the default path.

## License

MIT (SPDX-License-Identifier: MIT). See the `LICENSE` file at the root of the
melodic-software/claude-code-plugins repository.
