# claude-ops

A Claude Code plugin bundling three operations skills — one cohesive capability:
running Claude Code well over time. Observability reads what your sessions
actually did, troubleshooting tracks what upstream has broken, and changelog
integration keeps your repo current with what upstream has shipped.

## The three skills

| Skill | What it does |
|---|---|
| `/claude-ops:claude-observability` | Reads locally captured Claude Code telemetry — OTEL DuckDB store, collector, optional Aspire dashboard, hook-event JSONL, ccusage — and renders cross-session trend reports (`session`/`day`/`week`/`month`/`since:`/`all` scopes). Read-only except the explicit `clean` action, which prunes the JSONL log and OTEL store by age. |
| `/claude-ops:claude-troubleshooting` | Searches known Claude product GitHub bugs before you build on a feature, checks service health and model quality, and maintains a persistent registry of tracked issues (what they block, workarounds, follow-ups when fixed). Actions: `status` (default), `search`, `check-all`, `scan`, `list`, `quality`, `create`. |
| `/claude-ops:claude-code-changelog` | Ingests Claude Code changelog entries and integrates them into the current repo: `fetch` (read-only display), `diff` (impact triage, no edits), `status` (applied versions from git history), and `apply` (full explore → research → interview → implement pipeline, explicit user intent only). |

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install claude-ops@melodic-software
```

## How the skills adapt to your repo

The defaults are repo-agnostic and everything project-specific routes through
your own repository's context:

- **Observability data locations.** The OTEL store defaults to
  `<project-root>/.claude/observability/otel` and is overridable via the
  `CC_OTEL_STORE` env var (retention windows via `CC_OTEL_RETENTION_DAYS` /
  `CC_OTEL_BODY_RETENTION_DAYS`). The hook-event JSONL source is read from
  `<project-root>/.claude/observability/hook-events.jsonl` only when your own
  hooks emit it; every source degrades gracefully when absent.
- **Persistent state** lives under the plugin's own data directory
  (`${CLAUDE_PLUGIN_DATA}`): the troubleshooting issue registry
  (`registry.json`), `check-all` output, and `--write` observability reports.
  Nothing is written into your repository.
- **Work-item and docs integration.** Where the skills propose follow-up work
  items or cross-reference quirks/workaround docs, they use whatever tracker
  and docs your project has (e.g. `gh issue create`, your `CLAUDE.md` /
  `.claude/rules`) and skip silently when there is none.

## Requirements

Core flows need only `git`, `jq`, `gh` (authenticated), and `python3`.
Optional, for the OTEL pipeline: `otelcol-contrib` (collector), `duckdb`
(store queries), Docker (Aspire dashboard), and `npx` for ccusage. Every
skill reports missing optional tooling instead of failing.

## Configuration

This plugin has no `userConfig`. Variability is covered by the env vars above
and conventional project-relative defaults; the bundled scripts make no
outbound network calls except `gh`/`curl` reads of GitHub and Claude status
pages in the troubleshooting skill.

## License

MIT (SPDX-License-Identifier: MIT). See the LICENSE file at the root of the
melodic-software/claude-code-plugins repository.
