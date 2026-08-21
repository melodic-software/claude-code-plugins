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

### Skills

- **`/review:quality-gate [mode]`** — the single-lens checkpoint between "code works"
  and "code is ready". Modes: `self` (fresh-context self-review), `code`, `architecture`,
  `security`, `spec` (spec-fidelity — did the change deliver what the originating item, plan, or
  brief asked for), `close-out` (the same fidelity lens at spec-container scale — one cumulative
  pass over everything a container shipped, across however many PRs, against the container's own
  body; derives its own diff basis per execution shape), `downstream` (what the change breaks
  outside its own diff — callers, serialization boundaries, cross-service consumers), `pr`,
  `criteria`, `slice <name>`, `restatement`.
- **`/review:fanout [mode]`** — breadth review: fans out across the
  reviewer agents, the project's own per-concern review criteria docs, and optional
  orchestrator review plugins, then normalizes everything into one ranked findings report.
  Modes: default (auto-scales to diff size), `run-everything` (full roster), `fix` (applies
  the merged set of persisted findings — the only mutating mode).
- **`/review:code-review`** — CI code-review lane command for
  `melodic-software/ci-workflows` `claude-review.yml` (correctness /
  maintainability; security scoped out when a security lane exists).
- **`/review:security-review`** — CI security-review lane command for
  `claude-security-review.yml` (org-authored; built-in `/security-review`
  is unusable under Actions checkout).

## Requirements

- **git** — every reviewer works from diffs, branches, and history.
- **`gh` CLI, authenticated** — required by `ci-log-auditor` (all CI-run
  evidence routes through `gh api`) and by PR-scoped review flows; the agent
  stops with a remediation message when `gh` is missing or unauthenticated.
  Local-diff reviews without a CI/PR angle work without it.
- **Bash** for the agents' inline commands — Git Bash on native Windows
  (install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows));
  no standalone `jq` is required.

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
- **Graceful degrade.** Optional orchestrator plugins — `pr-review-toolkit` and `code-review` from
  the official marketplace, and `codex` from the OpenAI Codex marketplace — add adversarial breadth
  when installed; every path works without them. Claude Code's bundled `/code-review` command and
  the managed Code Review GitHub App service are two further surfaces, distinct from the
  `code-review` marketplace plugin despite the shared name. **`/review` is one of them, not this
  plugin**: per [code-review](https://code.claude.com/docs/en/code-review#review-a-diff-locally)
  (fetched 2026-08-10), "`/review` is an alias of `/code-review`; before v2.1.223, it was a separate
  command that ran a single-pass, read-only review of a GitHub pull request." A bare `/review` is
  that bundled reviewer, so name this plugin's skills by their namespaced commands
  (`/review:quality-gate`, `/review:fanout`) rather than abbreviating to the plugin name — the
  0.18.0 removal of the bare `/<skill>` alias already made the namespaced form the only one this
  plugin registers. See the Boundary sections of
  [`skills/quality-gate/context/pr.md`](skills/quality-gate/context/pr.md) and
  [`skills/fanout/SKILL.md`](skills/fanout/SKILL.md) for how each skill relates to all three.
- **Self-contained.** The severity baseline and all mode guidance ship inside the plugin
  and are referenced via `${CLAUDE_PLUGIN_ROOT}`.

## Findings location

Review findings persist to the topic-docs convention's memory tier, concern-scoped on the branch
axis. [`reference/topic-docs.md`](reference/topic-docs.md) owns where that resolves — the ladder,
its non-interactive collapse, and the `.work/reviews/<branch-slug>/` default — and the skills read it
rather than assuming a path shape. The memory root self-ignores (a `.gitignore` containing `*`,
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

MIT (SPDX-License-Identifier: MIT).
