# Design resolution — plugin-audit-port

```yaml
outcome: early-exit
tier: A-satisfied-by-interview
date: 2026-07-23
```

## Why no separate /planning:design pass

The design-significant threads for both plugins were resolved and owner-confirmed during
`/planning:interview` (4 frontier rounds, 15 branches, confirmed 2026-07-23 — ledger:
`.work/plugin-audit-port/interview-checklist.md`). The Brief in `PLAN.md` carries the resolved
contracts verbatim; a design pass would re-derive settled threads. This artifact records the
early-exit and the type/contract sketch the gate requires. `[FALLBACK — confirm or override]` —
surfaced in the plan's decisions table; the owner may still demand a full `/design` pass.

## Design-thread map (axis → resolution)

| Design axis | Resolution | Ledger branch |
|---|---|---|
| Module boundaries | Two standalone plugins (`context-guard`, `plugin-quality`); explicitly NOT an extension of `rate-limit-guard` and NOT joined to `review`/`skill-quality` | B1, B11, B12 |
| New types/contracts | Snapshot file, zones file, resolver CLI, tracked config file, evidence packet (sketches below) | B12, B15, B8 |
| Cross-module integration | Soft dependency via documented reader contract (file seam); no manifest `dependencies`; absent/stale → conservative fallback + visible notice | B13 |
| Execution topology | Two-phase audit: main-thread evidence capture → fresh NAMED subagent (never `context: fork`); basis in `PLAN.md`'s `[EXEC-SHAPE]` plugin-agent decision | B3, B7 |
| Configurability | Tracked `.claude/plugin-quality.md` per config-cascade; user-global `~/.claude/plugin-quality.md`; no `userConfig` v1 | B8 |
| External integration | Sink = backend-neutral work-item vocabulary; default `gh` issue with draft+confirm egress gate; resolution ladder | B2, B6, B14 |
| Observability | Zones SSOT readable by both consumers and the operator's statusline (kills display-vs-consumer drift) | B15 |
| Testability | Tee script `.test.sh` on the rate-limit-guard pattern; evals warranted for `audit`; skill-quality:check gate | B10 |

## Type/contract sketch

### 1. Context snapshot (context-guard writes; anyone reads)

Path: `~/.claude/context-guard/context/<session_id>.json` — one file per session, atomic
temp+rename write on every statusline refresh, last-write-wins per session.

```json
{
  "captured_at": "2026-07-23T17:41:02Z",
  "session_id": "abc123",
  "context_window": {
    "used_percentage": 62.4,
    "total_input_tokens": 118000,
    "total_output_tokens": 9200,
    "context_window_size": 200000,
    "current_usage": { "...": "raw statusline fields verbatim" }
  }
}
```

`context_window` copied verbatim from statusline stdin (field list re-verified against current
statusline doc at implementation). `captured_at` drives the staleness rule. Stale sibling files
pruned on write (implementation detail, not contract).

### 2. Zones file (optional machine-scope override) + resolver

Path: `~/.claude/context-guard/zones.json`. Shape (shipped defaults live in the resolver, not the
file — absent file = zero-config):

```json
{ "zones": [
  { "name": "smart",      "max_used_percentage": <N1> },
  { "name": "acceptable", "max_used_percentage": <N2> },
  { "name": "dumb" }
] }
```

Resolver: `context-zone.sh <session_id>` → prints `smart|acceptable|dumb|unknown` (+ staleness
handling). Exact default band numbers are a deferred Brief question — grounded during
implementation against current auto-compaction behavior.

### 3. Tracked consumer config (plugin-quality)

`.claude/plugin-quality.md` (project) + `.claude/plugin-quality.local.md` (overlay) +
`~/.claude/plugin-quality.md` (user-global), per config-cascade. Keys: sink, zone-behavior
criteria, repo-map overrides. Merge semantics declared in the plugin's reference doc.

### 4. Evidence packet (plugin-quality internal, compaction-proof)

Durable on-disk packet written by step 1 of the audit workflow; consumed by the fresh subagent in
step 2. Location + field list finalized at implementation (capture-broadly starting set locked in
Brief).
