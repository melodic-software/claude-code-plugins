---
description: "Read and report on locally captured Claude Code telemetry, OTEL DuckDB store, collector, optional Aspire dashboard, hook-event JSONL, ccusage, with cross-session trend reports and store pruning. Use when: 'claude observability', 'OTEL', 'collector', 'token burn rate', 'hook latency', 'cost breakdown', 'how am I doing'; read-only except the explicit clean action."
user-invocable: true
disable-model-invocation: false
argument-hint: "[scope|action]. Week (default), session, day, month, since:YYYY-MM-DD, all, clean [--keep-days N] [--dry-run] [--skill-usage-scope repo|user|data-dir]"
shell: bash
metadata:
  workflow-stage: operator
  summary: Report on locally captured telemetry. Token burn, cost, hook latency, trends
  cadence: weekly
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Repo slug: !`git rev-parse --show-toplevel 2>/dev/null | sed 's|.*/||' || echo "unknown"`
ccusage availability: !`command -v npx >/dev/null 2>&1 && echo "npx present" || echo "npx MISSING"`
Hook event log: !`bash "${CLAUDE_PLUGIN_ROOT}/skills/observability/scripts/probe-observability-state.sh" --hook-events 2>/dev/null || echo "unknown"`
OTEL collector :4318: !`bash -c 'source "${CLAUDE_PLUGIN_ROOT}/skills/observability/otel/net-probe.sh" && port_status 4318' 2>/dev/null || echo unknown`
OTEL store: !`bash "${CLAUDE_PLUGIN_ROOT}/skills/observability/scripts/probe-observability-state.sh" --otel-store 2>/dev/null || echo "unknown"`

## Purpose

**Single place to read Claude Code observability**, where to read telemetry, how the
collector/dashboard/store fit together, and cross-session trend reports. **CC** shorthand =
Claude Code CLI. See [context/operator-setup.md](context/operator-setup.md) "Naming".
Progressive disclosure lives in `context/` (read on demand. Do not recap inline).

**Read-only**, never writes user-visible state except a report file under
`${CLAUDE_PLUGIN_DATA}/reports/` (when `--write` is passed). Honors
[context/privacy.md](context/privacy.md).

**Not `/claude-ops:known-issues`**. That skill tracks Anthropic product bugs and GitHub issues.
This skill reads **your** captured telemetry and ops signals.

## Context ladder (read on demand)

| File | When |
|---|---|
| [context/read-routing.md](context/read-routing.md) | Ad-hoc "which source for this question?" |
| [context/otel-pipeline.md](context/otel-pipeline.md) | Collector/dashboard down, store empty, service health |
| [context/otel-queries.md](context/otel-queries.md) | DuckDB SQL, Aspire CLI, views |
| [context/operator-setup.md](context/operator-setup.md) | Install, env profile, retention scripts |
| [context/data-sources.md](context/data-sources.md) | JSONL + ccusage jq (batch reports) |
| [context/output-format.md](context/output-format.md) | Rendering scope reports |
| [context/privacy.md](context/privacy.md) | Before any user-visible output |

OTEL query and retention helpers live in `otel/` (private backends) with stable entry points in
`scripts/`. Machine provisioning owns the Collector configuration and all long-running service
and dashboard lifecycle.

## Arguments

`$ARGUMENTS`. Scope filter OR action. First token chooses behavior:

### Reporting scopes (default behavior)

| Scope | Window | Use case |
|---|---|---|
| `session` | current session only | quick check before `/clear` |
| `day` | last 24 hours | end-of-day review |
| `week` (**default**) | last 7 days | weekly retro complement |
| `month` | last 30 days | trend evaluation |
| `since:YYYY-MM-DD` | from explicit date | post-launch evaluation |
| `all` | no filter | full history |

Optional second token: `--write` (persist report to
`${CLAUDE_PLUGIN_DATA}/reports/claude-observability-<date>.md` instead of stdout).

When the scope is `week` or larger, optionally offer a self-contained HTML dashboard rendering
the same multi-metric trend report alongside the markdown (session/day stay markdown; markdown
remains the durable record).

### Maintenance actions

| Action | Args | Effect |
|---|---|---|
| `clean` | `[--keep-days N]` (default 30) `[--dry-run]` `[--quiet]` `[--skill-usage-scope repo\|user\|data-dir]` `[--skill-usage-dir REL]` `[--keep-skill-usage-days N]` (default 365) | Prune JSONL + OTEL store. See [context/read-routing.md](context/read-routing.md) "Retention" and `scripts/clean.sh`. Skill-usage pruning is **opt-in**: inert unless `--skill-usage-scope` is passed, and `data-dir` requires an explicit `--skill-usage-dir` rather than trusting `CLAUDE_PLUGIN_DATA` |

Action invocation: `/claude-ops:observability clean [flags]`.

**`clean` requires explicit user confirmation** before running when invoked by the model. Show
`--dry-run` output first unless user already passed `--dry-run` or explicitly ordered cleanup.

### Ad-hoc telemetry reads (no special action)

When the user asks to inspect traces, logs, metrics, or hook data outside a scope report:

1. Read [context/read-routing.md](context/read-routing.md). Pick source
2. Read [context/otel-queries.md](context/otel-queries.md) or [context/data-sources.md](context/data-sources.md). Run queries
3. Apply [context/privacy.md](context/privacy.md). Redact before responding

## Workflow. Scope reports

### 0. Dispatch. Action vs scope

If `$1 == "clean"`: shift, delegate to `scripts/clean.sh "$@"` and return its exit code.

```bash
if [[ "${1:-}" == "clean" ]]; then
  shift
  exec bash "${CLAUDE_PLUGIN_ROOT}/skills/observability/scripts/clean.sh" "$@"
fi
SCOPE="${1:-week}"
case "$SCOPE" in
  session|day|week|month|all) ;;
  since:*) ;;
  *) echo "Unknown scope: $SCOPE. Use session|day|week|month|since:YYYY-MM-DD|all|clean" >&2; exit 1 ;;
esac
```

### 1. Gather data sources

Read [context/data-sources.md](context/data-sources.md). Summary:

| Source | Path | What it provides |
|---|---|---|
| ccusage | MCP or CLI | Token counts, cost USD, billing blocks |
| Hook event log | `.claude/observability/hook-events.jsonl` (project-relative; present only if the consumer's hooks emit it) | Hook duration, exit codes |
| OTEL store | `$CC_OTEL_STORE/*.json` → DuckDB | Logs, metrics, spans. [context/otel-queries.md](context/otel-queries.md) |
| Auto-memory | `~/.claude/.../memory/feedback_*.md` | User-correction patterns |
| Git / GH | `git log`, `gh pr list` | Activity context |

### 2–5. Compute, privacy, render, output

Unchanged. [context/data-sources.md](context/data-sources.md), [context/privacy.md](context/privacy.md),
[context/output-format.md](context/output-format.md).

## Cross-references

- `/claude-ops:known-issues`. CC product bugs (not telemetry reads)

## Gotchas

- Empty stores are normal on first run. Degrade gracefully
- **`session_id` drift**. Use `cwd` + `branch` + time proximity
- **Stop hook unreliability**. Do not rely on Stop for aggregation
- **`cc_spans` / `cc_traces`**. Views skip bind until `cc-traces.json` has content

## What this skill does NOT do

- **Does not track GitHub bugs**. Invoke `/claude-ops:known-issues` via the Skill tool
- **Does not modify code**. Read-only
- **Does not replace built-in `/insights`** or your own retrospective workflow
- **Does not write to memory** unless user explicitly saves
