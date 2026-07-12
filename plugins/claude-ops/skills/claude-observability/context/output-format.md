# `/claude-observability` output format

Markdown report. Structured for quick visual scan + machine grep.

## Severity buckets

| Bucket | Rule | Action |
|---|---|---|
| `HIGH` | rate-limit projected exhaustion before window reset; hook p95 > 3s; ≥3 failed-then-fixed retries on same hook | act this session |
| `MEDIUM` | velocity > 25%/hr sustained; hook p95 in 1-3s; drift candidate (rule cites missing path); recurring 3-gram appearing 5+ times | review within sprint |
| `INFO` | trend tables, breakdowns, cost/token totals, calibration counts | reference only |

Severity is computed per finding, not per section. A section with all-INFO findings still renders.

## Skeleton

```markdown
# Claude observability — <SCOPE> (<window>)

Generated: <ISO timestamp>
Repo: <slug> · Branch: <name>

## Summary

- <one-line per HIGH finding, max 5>
- <one-line per MEDIUM finding, max 5>

## Token / cost (last <window>)

| Model | Input | Output | Cost USD |
|---|---:|---:|---:|
| claude-opus-4-8 | 1.2M | 0.4M | $X.XX |
| claude-sonnet-4-6 | 0.6M | 0.2M | $X.XX |
| **Total** | **1.8M** | **0.6M** | **$X.XX** |

5-hour blocks (current + prior 3): <inline summary>

## Rate-limit velocity

- five_hour: avg <V%>/hr, current used <U%>, projected 100% in <T hr> (resets in <R hr>) — <severity>
- seven_day: avg <V%>/hr, current used <U%>, projected exhaustion <date> — <severity>

<table of paired-sample deltas>

## Hook latency (top 10 by p95)

| Hook | Event | n | p50 ms | p95 ms | p99 ms | err % | Severity |
|---|---|---:|---:|---:|---:|---:|---|
| sarif-diagnostics | PostToolUse | 142 | 850 | 3200 | 4100 | 0% | HIGH |
| bash-lint | PostToolUse | 67 | 120 | 380 | 520 | 0% | INFO |

## Recurring patterns

3-grams appearing 5+ times:

- `12× PostToolUse:bash-lint → PostToolUse:bash-lint → PostToolUse:bash-lint`
- `7× PostToolUse:eol-normalizer → PostToolUse:bash-lint → PostToolUse:typescript-format`

Failed-then-fixed retries:

- `<hook>: <N> retries`

## Hallucination-guard catches

`PostToolUse` events from `cli-flag-verify` hook (advisory exit 1).

- Total: `<N>` violations · unique `<bin>:<sha16>` pairs: `<U>`

| Binary | Catches | Unique pairs | Severity |
|---|---:|---:|---|
| claude | 12 | 4 | MEDIUM |
| gh | 3 | 3 | INFO |

Top recurring (same `<bin>:<sha16>` ≥ 3×):

- `5× claude:<sha16>` — repeated hallucination, escalation candidate
- (or) `_no recurrences_`

## Drift candidates

- `MEDIUM` `<rule.md>` cites `<path>` — not tracked in repo
- (or) `No drift detected.`

## Calibration

- `<N>` side observations dismissed in window (memory feedback signal)
- (or) `No calibration data.`

## Activity context

- Commits: <N> · PRs opened: <N> · merged: <N>
```

## Rendering rules

- **Tables for ≥3 rows**, otherwise inline list
- **Top-N caps** prevent runaway reports: top 10 hooks, top 10 patterns, top 5 HIGH findings in summary
- **Counts before percents** in summary lines (`12× retries` not `0.85% of events`)
- **Currencies** always 2-decimal, prefixed `$`
- **Durations** ms when < 1000, otherwise `Xs` with one decimal
- **Empty sections** render with `_no data — <reason>_` not omitted (presence-of-section is itself signal)

## Severity coloring (terminal)

When stdout is a TTY, colorize severity tokens:

| Severity | ANSI |
|---|---|
| HIGH | red bold (`\e[1;31m`) |
| MEDIUM | yellow (`\e[33m`) |
| INFO | dim (`\e[2m`) |

Stripped when `--write` (markdown file persists clean).

## `--write` mode

Path: `${CLAUDE_PLUGIN_DATA}/reports/claude-observability-$(date +%Y-%m-%d).md` (create the `reports/` directory if absent). Same content. After write, print path on stdout (only) for the user to pick up.

Reports are working artifacts — copy one into the consumer project only if it is durably useful (rare).

## What this template intentionally omits

- Recommendations / action items — `/claude-observability` surfaces signals, user decides what to act on
- Per-session detail — aggregation hides per-session noise; use ccusage MCP directly for session drill-down
- Cross-repo data — out of scope; observability is project-local
