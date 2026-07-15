# Read routing — which source for which question

Operator setup (install, env, retention): [operator-setup.md](operator-setup.md). Pipeline:
[otel-pipeline.md](otel-pipeline.md). Queries: [otel-queries.md](otel-queries.md).

Batch reports and JSONL jq: this skill's scope actions. Product bugs: `/troubleshoot`.

**CC** = Claude Code CLI (not .NET app OTEL). Full naming table: [operator-setup.md](operator-setup.md)
"Naming".

## Three layers (do not conflate)

| Layer | What it captures | Persistent? |
|---|---|---|
| **OTEL → DuckDB store** | CC CLI logs, metrics, traces (spans) | Yes — hot NDJSON + cold Parquet |
| **OTEL → Aspire dashboard** | CC logs, metrics, traces (live in-memory) | **No** — restart drops history |
| **JSONL observability** | Hook timing | Yes — `.claude/observability/*.jsonl` |

```text
CC CLI ── OTLP :4318 ──▶ Collector ──┬── file ──▶ DuckDB (cc_logs, cc_metrics, cc_spans)  ← SSOT
                                     └── gRPC ──▶ Aspire :18888 (all 3 signals, optional UI)

Hooks ──▶ hook-events.jsonl
```

## Quick routing — "I need to know X"

| Question | Best path | Detail |
|---|---|---|
| Token/cost totals, per-model split, billing blocks | ccusage MCP or CLI | [data-sources.md](data-sources.md) §1 |
| Hook p95 latency, hook errors, recurring hook sequences | `hook-events.jsonl` | [data-sources.md](data-sources.md) §2 |
| Tool latency, API errors (historical) | DuckDB `cc_logs` | [otel-queries.md](otel-queries.md) |
| Token/cost metrics (historical) | DuckDB `cc_metrics` | [otel-queries.md](otel-queries.md) |
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
2. DuckDB for historical reads — project columns, filter, `LIMIT`.
3. Cold tier for multi-week trends — hot NDJSON full scans can take tens of seconds.
4. Aspire: always `--limit`; avoid `--follow` unless streaming is the goal.
5. Scope by `session_id`, `trace_id`, or time — one Collector file serves all worktrees.
6. ccusage for cost — do not reconstruct billing from OTEL metrics when ccusage is available.

## Retention (summary)

| Store | Knob | Default |
|---|---|---|
| OTEL structure (logs + traces) | `CC_OTEL_RETENTION_DAYS` | 7 days |
| OTEL API bodies (logs only) | `CC_OTEL_BODY_RETENTION_DAYS` | 2 days |
| JSONL hook events | `/observability clean --keep-days N` | 30 days |
| Aspire RAM | none | restart to reclaim |

Full prune mechanics: [operator-setup-retention.md](operator-setup-retention.md) "Pruning the store (retention) — two tiers".

## Anti-patterns

| Do not | Do instead |
|---|---|
| Use Aspire as historical SSOT | DuckDB hot + cold |
| Pull metrics or logs from Aspire | `cc_metrics` / `cc_logs` |
| `Read` whole `cc-*.json` files | DuckDB with `LIMIT` |
| Use SDK-path traces for full span tree | Direct CLI (#53954 — streaming may be `llm_request`-only) |

## Distinction from `/troubleshoot`

| Surface | Scope |
|---|---|
| **`/observability`** | **Your** telemetry — hooks, OTEL store, collector, dashboard, ccusage, trends |
| **`/troubleshoot`** | **Anthropic product** bugs — GitHub issue registry, health checks, workarounds |

CC behaving unexpectedly → `/troubleshoot search <feature>`. Reading what CC emitted → this file.
