---
description: "Read and report on locally captured Claude Code telemetry, OTEL DuckDB store, collector, optional Aspire dashboard, the per-session hook event log and hook-event JSONL, ccusage, with cross-session trend reports, a per-session report, and store pruning. Use when: 'claude observability', 'OTEL', 'collector', 'token burn rate', 'hook latency', 'cost breakdown', 'how am I doing', 'what did this session do', 'hook event log', 'which hooks fired'; read-only except the explicit clean action."
user-invocable: true
disable-model-invocation: false
argument-hint: "[scope|action]. Week (default), session, session:<id>, day, month, since:YYYY-MM-DD, all, clean [--keep-days N] [--dry-run] [--hook-root REL] [--skill-usage-scope repo|user|data-dir]"
shell: bash
metadata:
  workflow-stage: operator
  summary: Report on locally captured telemetry. Token burn, cost, hook latency, per-session activity
  cadence: weekly
---

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined into a single
invocation:

- Current branch, `git branch --show-current`
- Repo slug, `git rev-parse --show-toplevel | sed 's|.*/||'`

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as
separate body Bash calls rather than pre-compute lines: the harness runs a skill's whole pre-compute
block as one shell invocation, and a worktree-isolated session refuses a compound command that
contains git.

## Pre-computed context

ccusage availability: !`command -v npx >/dev/null 2>&1 && echo "npx present" || echo "npx MISSING"`
Hook log root (rendered option, empty or unrendered means the default `.observability/claude`): `${user_config.session_event_log_dir}`
Hook event log: !`bash "${CLAUDE_PLUGIN_ROOT}/skills/observability/scripts/probe-observability-state.sh" --hook-events --root "${user_config.session_event_log_dir}" 2>/dev/null || echo "unknown"`
Hook logging pipeline: !`bash "${CLAUDE_PLUGIN_ROOT}/skills/observability/scripts/probe-observability-state.sh" --pipeline --root "${user_config.session_event_log_dir}" --enabled "${user_config.session_event_log_enabled}" --categories "${user_config.session_event_log_categories}" --keep-sessions "${user_config.session_log_keep_sessions}" --keep-days "${user_config.session_log_keep_days}" --pre-prune-command "${user_config.session_log_pre_prune_command}" 2>/dev/null || echo "unknown"`
OTEL collector :4318: !`bash -c 'source "${CLAUDE_PLUGIN_ROOT}/skills/observability/otel/net-probe.sh" && port_status 4318' 2>/dev/null || echo unknown`
OTEL store: !`bash "${CLAUDE_PLUGIN_ROOT}/skills/observability/scripts/probe-observability-state.sh" --otel-store 2>/dev/null || echo "unknown"`

## Purpose

**Single place to read Claude Code observability**, where to read telemetry, how the
collector/dashboard/store fit together, cross-session trend reports, and what one session did
(which hooks fired, what was blocked, the event timeline). **CC** shorthand = Claude Code CLI.
See [context/operator-setup.md](context/operator-setup.md) "Naming". Progressive disclosure
lives in `context/` (read on demand. Do not recap inline).

**Read-only**, never writes user-visible state except a report file under
`${CLAUDE_PLUGIN_DATA}/reports/` (when `--write` is passed). Honors
[context/privacy.md](context/privacy.md). Turning the hook logging pipeline on or off, and
placing its guard, is `/claude-ops:setup`'s job; this skill reports what is in effect.

**Not `/claude-ops:known-issues`**. That skill tracks Anthropic product bugs and GitHub issues.
This skill reads **your** captured telemetry and ops signals.

## Context ladder (read on demand)

| File | When |
|---|---|
| [context/read-routing.md](context/read-routing.md) | Ad-hoc "which source for this question?" |
| [context/otel-pipeline.md](context/otel-pipeline.md) | Collector/dashboard down, store empty, service health |
| [context/otel-queries.md](context/otel-queries.md) | DuckDB SQL, Aspire CLI, views |
| [context/operator-setup.md](context/operator-setup.md) | Install, env profile, retention scripts |
| [context/operator-setup-collector-daemon.md](context/operator-setup-collector-daemon.md) | Collector/Aspire service down or unhealthy, lifecycle repair |
| [context/operator-setup-retention.md](context/operator-setup-retention.md) | Prune mechanics, retention knobs, scheduled prune task |
| [context/operator-setup-emission-privacy.md](context/operator-setup-emission-privacy.md) | Emission tiers, content-capture keys, privacy toggle |
| [context/data-sources.md](context/data-sources.md) | JSONL + ccusage jq (batch reports, the per-session report, toggles in effect) |
| [context/output-format.md](context/output-format.md) | Rendering scope reports and the per-session report |
| [context/privacy.md](context/privacy.md) | Before any user-visible output |

OTEL query and retention helpers live in `otel/` (private backends) with stable entry points in
`scripts/`. Machine provisioning owns the Collector configuration and all long-running service
and dashboard lifecycle.

## Arguments

`$ARGUMENTS`. Scope filter OR action. First token chooses behavior:

### Reporting scopes (default behavior)

| Scope | Window | Use case |
|---|---|---|
| `session` | the newest session file (by mtime) under the hook log root | what this session did, before `/clear` |
| `session:<id>` | one named session file, `sessions/<id>.jsonl` | a session the timeline or another report named |
| `day` | last 24 hours | end-of-day review |
| `week` (**default**) | last 7 days | weekly retro complement |
| `month` | last 30 days | trend evaluation |
| `since:YYYY-MM-DD` | from explicit date | post-launch evaluation |
| `all` | no filter | full history |

The two session scopes render the per-session skeleton in
[context/output-format.md](context/output-format.md); every other scope renders the whole-root
report. Optional tokens: `--write` (persist the report to
`${CLAUDE_PLUGIN_DATA}/reports/claude-observability-<date>.md` instead of stdout) and
`--hook-root REL` (read a different hook log root for this run; the rendered option above is
the default).

When the scope is `week` or larger, optionally offer a self-contained HTML dashboard rendering
the same multi-metric trend report alongside the markdown (session/day stay markdown; markdown
remains the durable record).

### Maintenance actions

| Action | Args | Effect |
|---|---|---|
| `clean` | `[--keep-days N]` (default 30) `[--dry-run]` `[--quiet]` `[--hook-root REL]` `[--skill-usage-scope repo\|user\|data-dir]` `[--skill-usage-dir REL]` `[--keep-skill-usage-days N]` (default 365) | Prune the hook log root (the shared file line by line, session files untouched for the window whole, stale `prune-pending/` sets regardless of the logging switch), the retired shared file while it exists, and the OTEL store. See [context/read-routing.md](context/read-routing.md) "Retention" and `scripts/clean.sh`. Skill-usage pruning is **opt-in**: inert unless `--skill-usage-scope` is passed, and `data-dir` requires an explicit `--skill-usage-dir` rather than trusting `CLAUDE_PLUGIN_DATA` |

Action invocation: `/claude-ops:observability clean [flags]`.

**`clean` requires explicit user confirmation** before running when invoked by the model. Show
`--dry-run` output first unless user already passed `--dry-run` or explicitly ordered cleanup.
Routine retention (newest N sessions or the last N days) is the `SessionEnd` hook's job while
`session_event_log_enabled` is on; `clean` is the operator's explicit sweep.

### Ad-hoc telemetry reads (no special action)

When the user asks to inspect traces, logs, metrics, or hook data outside a scope report:

1. Read [context/read-routing.md](context/read-routing.md). Pick source
2. Read [context/otel-queries.md](context/otel-queries.md) or [context/data-sources.md](context/data-sources.md). Run queries
3. Apply [context/privacy.md](context/privacy.md). Redact before responding

## Workflow. Scope reports

### 0. Dispatch. Action vs scope

If the first argument is `clean`: delegate to `scripts/clean.sh` with the remaining arguments and return its exit code.

```bash
if [[ "${1:-}" == "clean" ]]; then
  shift
  exec bash "${CLAUDE_PLUGIN_ROOT}/skills/observability/scripts/clean.sh" "$@"
fi
SCOPE="${1:-week}"
case "$SCOPE" in
  session|day|week|month|all) ;;
  session:*|since:*) ;;
  *) echo "Unknown scope: $SCOPE. Use session|session:<id>|day|week|month|since:YYYY-MM-DD|all|clean" >&2; exit 1 ;;
esac
```

### 1. Gather data sources

Read [context/data-sources.md](context/data-sources.md). Summary:

| Source | Path | What it provides |
|---|---|---|
| ccusage | MCP or CLI | Token counts, cost USD, billing blocks |
| Hook log root | `<session_event_log_dir>/` (`.observability/claude` by default, project-relative): `sessions/<session_id>.jsonl` and the shared `hook-events.jsonl`; present only once a producer wrote there | Hook duration, exit codes, what was blocked, the per-session event timeline |
| Pipeline state | `scripts/probe-observability-state.sh --pipeline` (the "Hook logging pipeline" line above) | Toggles, retention, guard state, stale prune sets |
| OTEL store | `$CC_OTEL_STORE/*.json` → DuckDB | Logs, metrics, spans. [context/otel-queries.md](context/otel-queries.md) |
| Auto-memory | `~/.claude/.../memory/feedback_*.md` | User-correction patterns |
| Git / GH | `git log`, `gh pr list` | Activity context |

### 2–5. Compute, privacy, render, output

Compute the sections per [context/data-sources.md](context/data-sources.md), redact per
[context/privacy.md](context/privacy.md), and render per
[context/output-format.md](context/output-format.md). Every report ends with the "Toggles and
retention in effect" section, the six probe lines verbatim.

## Cross-references

- `/claude-ops:known-issues`. CC product bugs (not telemetry reads)
- `/claude-ops:setup`. Turns the hook logging pipeline on, places the guard, migrates the retired shared-file location

## Gotchas

- Empty stores are normal on first run. Degrade gracefully
- **`session_id` joins only per-session files**. Rows in `sessions/<id>.jsonl` carry the id; rows in the shared `hook-events.jsonl` do not, and are never attributed to a session (say "legacy rows, shared file, time proximity only"). OTEL rows join on `session_id` as before; `cwd` + `branch` + time proximity is the fallback for a producer that sends none
- **Per-hook duration per session covers producers that emit `data.session_id`** (the nine claude-ops audit hooks). Other hooks appear in the whole-root tables only
- **Hooks run in parallel**. Row order within one second is write order, not fire order; group by `prompt_id` or `tool_use_id`, not by adjacency
- **Stop hook unreliability**. Do not rely on Stop for aggregation
- **`cc_spans` / `cc_traces`**. Views skip bind until `cc-traces.json` has content

## What this skill does NOT do

- **Does not track GitHub bugs**. Invoke `/claude-ops:known-issues` via the Skill tool
- **Does not modify code**. Read-only
- **Does not configure the pipeline**. `/claude-ops:setup` owns the toggles and the guard
- **Does not replace built-in `/insights`** or your own retrospective workflow
- **Does not write to memory** unless user explicitly saves
