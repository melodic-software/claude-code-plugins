# Topic-docs placement — where this plugin's artifacts land

How `/implementation:implement`, `/implementation:implement-dispatch`, `/implementation:verify-changes`,
and `/implementation:verify-improvement` resolve where generated documents land in a consuming repo.
These skills read this one document; none bakes its own paths.

Implements the topic-docs convention:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>.
The contract owns every general rule — tiers, schema, resolution order, slug spec, runtime guards,
no-project-root fallback, non-interactive/forked mode, the prune-with-pointer lifecycle with its
redaction bar. This document records only this plugin's deltas.

The sibling `artifact-protocol.md` defines the shared lifecycle artifact names and producer/consumer
behavior; this binding and topic-docs remain authoritative for their placement.

## What this plugin writes, per tier

| Artifact | Tier | Location (default) |
|---|---|---|
| `PLAN.md` Plan section + progress marks (phase tags, step boxes) | Contract | `docs/topics/<slug>/PLAN.md`, committed on the task branch |
| `DEVIATIONS.md` (autonomous-run deviation log, reviewed at PR time) | Contract | pinned beside `PLAN.md` in the topic's contract slice |
| Verification manifest (distilled, `verified_at_sha`-keyed; meets the contract's redaction bar) | Contract | `docs/topics/<slug>/verification/` |
| Baselines (machine-bound measurements) | Memory | `.work/<slug>/baselines/` — never committed |
| Raw verification captures | Memory | `.work/<slug>/scratch/` |
| Status summary | Memory | `.work/<slug>/` |
| Timestamped handoff notes | Memory | `.work/handoffs/` — `/session-flow:handoff` owns that surface; the fallback note (plugin absent) lands in the same home |

`contract_tier: local` moves the contract rows into the memory slice with an identical layout —
the contract's solo/offline mode. Roots are configurable via the concern file's `contract_dir` /
`memory_dir` keys.

**Phase-commit rule:** each implementation phase's plan updates ride the same commit as that
phase's source changes — one commit, one story; memory-tier files never enter the commit.
