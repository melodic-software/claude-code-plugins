# Read routing: which source for which question

Operator setup (install, env, retention): [operator-setup.md](operator-setup.md). Pipeline:
[otel-pipeline.md](otel-pipeline.md). Queries: [otel-queries.md](otel-queries.md).

Batch reports and JSONL jq: this skill's scope actions. Product bugs: `/harness-ops:known-issues`.

**CC** = Claude Code CLI (not .NET app OTEL). Full naming table: [operator-setup.md](operator-setup.md)
"Naming".

## Three layers (do not conflate)

| Layer | What it captures | Persistent? |
|---|---|---|
| **OTEL → DuckDB store** | CC CLI logs, metrics, traces (spans) | Yes, hot NDJSON + cold Parquet |
| **OTEL → Aspire dashboard** | CC logs, metrics, traces (live in-memory) | **No**, restart drops history |
| **JSONL observability** | Hook timing, per-session hook event log | Yes, the hook log root (`.observability/claude/` by default): `sessions/<session_id>.jsonl` and the shared `hook-events.jsonl` plus its rotated `hook-events.jsonl.1` |

```text
CC CLI ── OTLP :4318 ──▶ Collector ──┬── file ──▶ DuckDB (cc_logs, cc_metrics, cc_spans)  ← SSOT
                                     └── gRPC ──▶ Aspire :18888 (all 3 signals, optional UI)

Hooks ──▶ envelope ──▶ sink ──┬── data.session_id ──▶ <root>/sessions/<session_id>.jsonl  (source: envelope)
                              └── no session id  ──▶ <root>/hook-events.jsonl[.1]         (legacy shape)
Every event ──▶ hooks module (opt-in, mods on) ──▶ session-event-log.sh ──▶ <root>/sessions/<session_id>.jsonl  (source: event-log)
```

The root is the plugin's `session_event_log_dir` option (project-relative, self-ignoring
`.gitignore` inside). The per-session event log is written by the plugin's hooks module, so a
session where mods are off, or where the built-in `sec-default` guard holds `classic.*` events,
has `source: envelope` rows at most, never `event-log` rows. The skill-usage store and the OTEL store stay under `.claude/observability/`.

## Quick routing: "I need to know X"

| Question | Best path | Detail |
|---|---|---|
| Token/cost totals, per-model split, billing blocks | ccusage MCP or CLI | [data-sources.md](data-sources.md) §1 |
| Hook p95 latency, hook errors, recurring hook sequences | the hook log root (`sessions/*.jsonl` + `hook-events.jsonl` + `hook-events.jsonl.1`) | [data-sources.md](data-sources.md) §2 |
| What one session did: hooks fired, blocked, rewrote, per-hook duration, the event timeline | `sessions/<session_id>.jsonl` (`session` / `session:<id>` scope) | [data-sources.md](data-sources.md) §2.5 |
| Which hook-logging toggles and retention are in effect, guard state, stale prune sets | `probe-observability-state.sh --pipeline` | [data-sources.md](data-sources.md) §2.6 |
| Why most installed skills never get used, whether starved by the listing budget, unreachable, or simply unobserved | `/harness-ops:audit-skill-visibility` | That skill owns interpretation of skill-usage data; this skill owns the store, the OTEL pipeline, and retention |
| Tool latency, API errors (historical) | DuckDB `cc_logs` | [otel-queries.md](otel-queries.md) |
| Token/cost metrics (historical) | DuckDB `cc_metrics` | [otel-queries.md](otel-queries.md) |
| Cache health, is prompt caching working | DuckDB `cc_metrics`, `cacheRead` vs `cacheCreation` per model, for history | [otel-queries.md](otel-queries.md) |
| Likely cause of the latest prompt-cache miss in this Claude Code session | `/usage` (the Prompt cache line names a likely cause) and the status line `prompt_cache.last_miss_cause`. Requires Claude Code v2.1.260 or later. Cause names include `tools_changed`, `system_prompt_changed`, `ttl_expired_5m`, and `likely_server_side`. The object is null until the first miss, and again when Claude Code could not identify a cause. **Basis:** [statusline: last miss cause](https://code.claude.com/docs/en/statusline#last-miss-cause) and [prompt caching](https://code.claude.com/docs/en/prompt-caching). **As of:** 2026-09-28. **Recheck:** either page drops `last_miss_cause` or the version floor | This row. DuckDB ratios do not name a cause |
| Cache health for an API APPLICATION's own traffic (not a Claude Code session) | Out of scope here: the platform's cache diagnostics API (beta) reports per-request miss reasons (`messages_changed`, `system_changed`, `tools_changed`, `model_changed`); resolve it from `platform.claude.com/docs/en/build-with-claude/cache-diagnostics` (verified 2026-09-09; recheck on that page changing) | This skill reads local Claude Code telemetry only |
| Trace span tree | DuckDB `cc_spans` | [otel-queries.md](otel-queries.md) |
| Trace summary (duration, span count) | DuckDB `cc_traces` | [otel-queries.md](otel-queries.md) |
| Prompt/API bodies (recent hot window) | DuckDB `cc_logs` | Bodies age at `CC_OTEL_BODY_RETENTION_DAYS` (default 2) |
| Months-long structure trends | `cc_*_cold()` macros | [otel-queries.md](otel-queries.md) |
| Live telemetry UI while session runs | Aspire HTTP or CLI (`--limit`) | [otel-queries.md](otel-queries.md) |

**Default:** DuckDB first. Aspire optional for live tail only.

## Signal × time (OTEL)

| Signal | Historical (DuckDB) | Live (Aspire) |
|---|---|---|
| Logs | `cc_logs`, `cc_logs_cold()` | forwarded (in-memory window) |
| Metrics | `cc_metrics`, `cc_metrics_cold()` | forwarded (in-memory window) |
| Traces | `cc_spans`, `cc_spans_cold()`, `cc_traces` | forwarded (in-memory window) |

## Token-efficient read rules

1. Never dump raw OTLP JSON or full `body` / `user_prompt` unless the task requires verbatim content.
2. DuckDB for historical reads: project columns, filter, `LIMIT`.
3. Cold tier for multi-week trends, since hot NDJSON full scans can take tens of seconds.
4. Aspire: always `--limit`; avoid `--follow` unless streaming is the goal.
5. Scope by `session_id`, `trace_id`, or time, since one Collector file serves all worktrees.
6. ccusage for cost. Do not reconstruct billing from OTEL metrics when ccusage is available.

## Retention

Retention knobs and their defaults are defined once in
[operator-setup-retention.md](operator-setup-retention.md#retention-knobs); full prune
mechanics in the same file, "Pruning the store (retention): two tiers". (Aspire holds
telemetry in RAM only, so restart to reclaim.)

## Anti-patterns

| Do not | Do instead |
|---|---|
| Use Aspire as historical SSOT | DuckDB hot + cold |
| Pull metrics or logs from Aspire | `cc_metrics` / `cc_logs` |
| `Read` whole `cc-*.json` files | DuckDB with `LIMIT` |
| Use SDK-path traces for full span tree | Direct CLI (see the issue note below) |

On the last row: `anthropics/claude-code#53954` reports that in streaming mode the enhanced-telemetry
beta emits `claude_code.llm_request` only, with the interaction, tool, and tool-execution spans
missing. The issue is closed as not planned, so the direct-CLI path stays the one that yields a
full span tree. Basis: `gh api repos/anthropics/claude-code/issues/53954`. Verified 2026-09-06
against Claude Code 2.1.263. Recheck when the issue reopens or closes as completed, or when a run
on this machine returns interaction spans from the SDK path; route the recheck through
`/harness-ops:known-issues check-all`.

## Distinction from `/harness-ops:known-issues`

| Surface | Scope |
|---|---|
| **`/harness-ops:observability`** | **Your** telemetry: hooks, OTEL store, collector, dashboard, ccusage, trends |
| **`/harness-ops:known-issues`** | **Anthropic product** bugs: GitHub issue registry, health checks, workarounds |

CC behaving unexpectedly → invoke `/harness-ops:known-issues search <feature>` via the Skill tool. Reading what CC emitted → this file.
