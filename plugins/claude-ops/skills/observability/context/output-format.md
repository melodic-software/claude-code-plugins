# `/observability` output format

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
| <model> | 1.2M | 0.4M | $X.XX |
| <model> | 0.6M | 0.2M | $X.XX |
| **Total** | **1.8M** | **0.6M** | **$X.XX** |

5-hour blocks (current + prior 3): <inline summary>

Cost USD is a list-rate estimate, not a bill: ccusage prices tokens at public per-token list
rates, while subscription usage is plan-priced.

## Cache health (last <window>)

| Model | Cache read | Cache creation | Read : create |
|---|---:|---:|---:|
| <model> | 8.4M | 0.9M | 9.3:1 |
| <model> | 0.5M | 2.6M | 0.2:1 |
| **Total** | **8.9M** | **3.5M** | **2.5:1** |

A high read-to-creation ratio means caching is working. Creation staying high turn after turn means
something keeps changing the request prefix — causes:
<https://code.claude.com/docs/en/prompt-caching#actions-that-invalidate-the-cache>

## Rate-limit velocity

- five_hour: avg <V%>/hr, current used <U%>, projected 100% in <T hr> (resets in <R hr>) — <severity>
- seven_day: avg <V%>/hr, current used <U%>, projected exhaustion <date> — <severity>

<table of paired-sample deltas>

## Hook latency (top 10 by p95)

| Hook | Event | n | p50 ms | p95 ms | p99 ms | err % | Severity |
|---|---|---:|---:|---:|---:|---:|---|
| sarif-diagnostics | PostToolUse | 142 | 850 | 3200 | 4100 | 0% | HIGH |
| bash-format | PostToolUse | 67 | 120 | 380 | 520 | 0% | INFO |

## Recurring patterns

3-grams appearing 5+ times:

- `12× PostToolUse:bash-format → PostToolUse:bash-format → PostToolUse:bash-format`
- `7× PostToolUse:eol-normalizer → PostToolUse:bash-format → PostToolUse:typescript-format`

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
- **Cache health is reported, never graded** — upstream documents the read-to-creation direction but
  publishes no threshold, so any HIGH/MEDIUM cutoff would be invented here rather than sourced. It
  is also the one section sourced from the OTEL store rather than ccusage, which is why it sits
  apart from Token / cost instead of adding columns to it
- **The Token / cost caveat line is fixed copy** — Claude Code documents the same list-rate
  limitation for its own locally computed dollar figures
  (<https://code.claude.com/docs/en/costs.md>, verified 2026-08-04)

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

- Recommendations / action items — `/observability` surfaces signals, user decides what to act on
- Per-session detail — aggregation hides per-session noise; use ccusage MCP directly for session drill-down
- Cross-repo data — out of scope; observability is project-local
