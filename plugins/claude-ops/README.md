# claude-ops

A Claude Code plugin for running Claude Code well over time — one cohesive
capability across three skills and a family of telemetry-emitter hooks.
Observability reads what your sessions actually did, troubleshooting tracks what
upstream has broken, changelog integration keeps your repo current with what
upstream has shipped, and the `*-audit` hooks feed observability with per-hook
execution telemetry Claude Code's native OTEL cannot see.

## The three skills

| Skill | What it does |
|---|---|
| `/claude-ops:claude-observability` | Reads locally captured Claude Code telemetry — OTEL DuckDB store, collector, optional Aspire dashboard, hook-event JSONL, ccusage — and renders cross-session trend reports (`session`/`day`/`week`/`month`/`since:`/`all` scopes). Read-only except the explicit `clean` action, which prunes the JSONL log and OTEL store by age. |
| `/claude-ops:claude-troubleshooting` | Searches known Claude product GitHub bugs before you build on a feature, checks service health and model quality, and maintains a persistent registry of tracked issues (what they block, workarounds, follow-ups when fixed). Actions: `status` (default), `search`, `check-all`, `scan`, `list`, `quality`, `create`. |
| `/claude-ops:claude-code-changelog` | Ingests Claude Code changelog entries and integrates them into the current repo: `fetch` (read-only display), `diff` (impact triage, no edits), `status` (applied versions from git history), and `apply` (full explore → research → interview → implement pipeline, explicit user intent only). |

## The audit hooks

Seven advisory `*-audit` hooks emit the marketplace [hook-telemetry
envelope](../../docs/conventions/hook-telemetry/README.md) — one JSON event per
run carrying that hook's own `duration_ms`, outcome, and a privacy-safe subject.
Each is independently toggleable via `HOOK_<NAME>_ENABLED=false` and is a no-op
until a consumer wires a sink (below).

| Hook | Event | Emits |
|---|---|---|
| `api-error-audit` | StopFailure | API turn-failure `error_type` (never the message body) |
| `config-change-audit` | ConfigChange | the mutated `config_source` |
| `instructions-loaded-audit` | InstructionsLoaded | `<file>:<load_reason>` (session_start filtered by default) |
| `permission-denied-audit` | PermissionDenied | classifier denials, `Bash:<first-token>` subject |
| `pre-compact-audit` | PreCompact | compaction `trigger` (`manual`/`auto`) |
| `skill-usage-audit` | PostToolUse (`Skill`) | skill invocations; also writes a `skill-usage.jsonl` second store |
| `tool-failure-audit` | PostToolUseFailure | Write/Edit/Bash failures, privacy-safe subject |

None captures a command body, file path, error message, or argument body — only
category labels and privacy-safe subjects.

### Wiring the reference sink

A migrated emitter is inert without a consumer. `hooks/hook-telemetry-sink.sh`
is a reference sink: it reads an envelope on stdin and appends one line to
`<project-root>/.claude/observability/hook-events.jsonl` — exactly the shape the
`claude-observability` skill reads. Wire it with a relative, team-shared path in
your `settings.json` (Claude Code injects `env` values literally, so relative is
the clone-portable form):

```json
{
  "env": {
    "HOOK_TELEMETRY_SINK": ".claude/plugins/.../claude-ops/hooks/hook-telemetry-sink.sh"
  }
}
```

Any envelope producer (this plugin's hooks, guardrails, the formatters) then
flows into the same store. The sink is fire-and-forget and best-effort — a slow
or absent sink silently drops the event; it is for observability, not
audit-of-record.

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
- **Persistent state** defaults to the plugin's own per-machine data directory
  (`${CLAUDE_PLUGIN_DATA}`): the troubleshooting issue registry
  (`registry.json`), `check-all` output, and `--write` observability reports.
  By default nothing is written into your repository. Opt in for the registry
  via the `registry_dir` option (see Configuration) to keep it git-tracked and
  team-shared inside your repo instead.
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

Two `userConfig` options:

- **`registry_dir`** (string, optional) — project-relative directory for the
  claude-troubleshooting issue registry (`registry.json`). Set it to keep the
  registry inside your repo (git-tracked, team-shared) instead of the
  per-machine plugin data directory; leave unset to use `${CLAUDE_PLUGIN_DATA}`.
- **`skill_usage_dir`** (string, optional) — project-relative directory where
  `skill-usage-audit` writes its `skill-usage.jsonl` second store (the
  "measuring skills" record, separate from the telemetry envelope); leave unset
  to use `.claude/observability`.

Remaining variability is covered by the env vars above and conventional
project-relative defaults; the bundled scripts make no outbound network calls
except `gh`/`curl` reads of GitHub and Claude status pages in the
troubleshooting skill.

## License

MIT (SPDX-License-Identifier: MIT). See the LICENSE file at the root of the
melodic-software/claude-code-plugins repository.
