# codebase-health

A Claude Code plugin for repo-wide drift auditing: it verifies that a codebase's **factual claims** —
in docs, config, code, and architecture notes — still match reality. Every claim is checked against
ground truth via a parallel per-file subagent fan-out, findings are severity-rated, and the audit
reports them read-only — remediation is delegated to the implementation/verification lanes.

Distinct from diff/PR review (which judges a change) and from Claude Code configuration audits (which
check `settings.json` / hooks / permissions): this plugin verifies whether the repo's own written
claims about itself are true.

| Skill | What it does |
|---|---|
| `/codebase-health:audit` | Runs the audit — prime conventions, fan out claim-extraction per file, independently validate, severity-rate, and report read-only; remediation is delegated to the implementation/verification lanes. |
| `/codebase-health:setup` | `check` inspects the tracked `.claude/codebase-health.md` config read-only across its merge layers; `apply` interviews the user, infers targets from the layout, and writes the config. |

## The audit

Four phases (0–3): prime the repo's conventions, discover via per-file fan-out, independently
validate each finding (a separate agent re-verifies — never self-review), then categorize and present
in a severity-rated table with a verified-non-issues proof-of-thoroughness list, drift patterns, fix
priority, enforcement escalation, and config-gap observations. Bare invocation is read-only — it
reports and stops.

Remediation is not owned here — fixing, verifying, self-reviewing, and retrospecting are delegated to
the dedicated lanes: `/implementation:implement` (fix) and `/verification:confirm` (verify), used as
soft dependencies when those plugins are installed. The explicit `--fix` flag hands the Phase 3
findings off to those lanes rather than fixing inline; when they are absent, the findings table is the
handoff and remediation is manual in the reported fix-priority order.

```shell
/codebase-health:audit                      # report-only audit of every configured dimension (scope-gated)
/codebase-health:audit docs/ --docs-only    # one dimension, scoped to a subtree, report-only
/codebase-health:audit README.md --fix      # scoped, then hand findings to the remediation lanes
```

Dimension filters (`--docs-only`, `--code-only`, `--config-only`, `--arch-only`) are mutually
exclusive. A scope path narrows the file set. An unscoped whole-repo run is gated — the skill
requires a scope, a filter, or explicit confirmation before fanning out, because a full fan-out spans
every doc/config/source file.

## Configurable audit dimensions

What the audit reads and how it verifies claims is **not baked in** — it comes from the consuming
repo's tracked config, resolved additively across three layers:

1. `~/.claude/codebase-health.md` — user-global base (optional)
2. `.claude/codebase-health.md` — team config (tracked)
3. `.claude/codebase-health.local.md` — personal overlay (gitignored)

Each dimension declares `primary-sources` (globs where claims live), `verification-sources` (globs
where claims are checked against ground truth), and `example-claims` (concrete `{ claim, verify-via }`
rows that teach the extraction pass what drift looks like in THIS repo). The four bundled dimensions
are `documentation`, `configuration`, `code-quality`, and `architecture`; the config may tune their
globs, remove a dimension, or add custom ones.

When no config is present, the audit infers targets from the repo layout, uses them, and offers to
persist the inference via `/codebase-health:setup apply` — so the next run is deterministic. It never
hardcodes a repo's layout.

```shell
/codebase-health:setup check   # inspect the effective config read-only (default)
/codebase-health:setup apply   # interview + write .claude/codebase-health.md (re-runnable)
```

Add `.claude/*.local.*` to your `.gitignore` so personal overlays stay out of version control while
team config stays tracked.

## Consumer conventions

Phase 0 reads the consuming repo's own `CLAUDE.md` / `AGENTS.md` / `.claude/rules/` to learn what
"correct" looks like — a claim contradicting those conventions is a finding; one following them is a
verified non-issue. Nothing project-specific is baked into the plugin.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install codebase-health@melodic-software
```

## Configuration

No `userConfig` — audit targets flow through the tracked `.claude/codebase-health.md` config seam
above (written by `/codebase-health:setup apply`). No hooks, no MCP servers, no bundled scripts, no network
calls of its own (Phase 2 may use whatever documentation-research tools your setup provides). State:
the audit reads and writes only the consumer's own files under the scope you give it.

## License

MIT (SPDX-License-Identifier: MIT).
