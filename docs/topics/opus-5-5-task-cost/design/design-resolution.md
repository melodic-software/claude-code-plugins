---
outcome: early-exit
tier: B
date: 2026-10-01
---

# Design resolution: opus-5-5-task-cost

Tier B (light design). Most of the change set is documentation pointers, one rule file, row text in
an audit catalog, and one research-gate row. Two pieces introduce something new, and both are
localized:

- **Per-phase model routing (Q20).** The plan template's per-phase routing table (`Phase | Surface |
  Basis`) gains a `Model` column with three values: `sonnet` (well-scoped), `opus` (complex, and the
  default for unrouted work) and `frontier` (security-surface classes, unchanged). One new agent
  definition, `implementation:scoped-implementer` (`model: sonnet`, `effort: medium`), receives the
  `sonnet` phases. The existing `implementation:implementer` (`opus`, `high`) stays the floor for
  any dispatch with no plan row. No new type or cross-module contract beyond that column and the
  agent name that implement-dispatch reads.
- **Observability `compare` action (Q22).** A new script, a SQL file and a test file follow the
  existing `latency` action's shape (`hook-latency.sh` + `otel/hook-latency.sql`). It reads `effort`
  from `attributes_list` and does not change the `cc-otel.sql` projection, because adding a column
  would change the cold Parquet schema (`prune-compact.sh:118`).

Type sketch for the compare output (tab-separated rows the script renders):

```text
tokens:  session | model | effort ("none" when absent) | type (input|output|cacheRead|cacheCreation) | sum
cost:    session | metric_usd | events_usd | gap_usd | api_requests | status (match|events short|events exceed metric)
```

No design threads remain open. The model-column criteria and the second-agent decision were settled
in the plan's Open Decisions round on 2026-10-01 and by the effort-pin owner session.
