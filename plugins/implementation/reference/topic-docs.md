# Topic-docs placement — where this plugin's artifacts land

How `/implementation:implement` and `/implementation:implement-dispatch` resolve where generated
documents land in a consuming repo. These skills read this one document; neither bakes its own paths.

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
| `PLAN.md` progress marks (phase tags, step boxes) — the plan is produced by a planning pass; this plugin marks progress on it | Contract | `docs/topics/<slug>/PLAN.md`, committed on the task branch |
| `DEVIATIONS.md` (autonomous-run deviation log, reviewed at PR time) | Contract | pinned beside `PLAN.md` in the topic's contract slice |
| Status summary | Memory | `.work/<slug>/` |
| Timestamped handoff notes | Memory | `.work/handoffs/` — `/session-flow:handoff` owns that surface; the fallback note (plugin absent) lands in the same home |

`contract_tier: local` moves the contract rows into the memory slice with an identical layout —
the contract's solo/offline mode. Roots are configurable via the concern file's `contract_dir` /
`memory_dir` keys.

Verification manifests and baselines are the `verification` plugin's artifacts (its own binding owns
their placement); this plugin does not write them.

**Phase-commit rule:** each implementation phase's plan updates ride the same commit as that
phase's source changes — one commit, one story; memory-tier files never enter the commit. Per the
contract's visibility rules (≥ 2.0.0) this is also what makes plan progress visible to isolated
contexts: a spawned worktree or dispatched worker sees the contract slice only as **committed**
state, so uncommitted plan marks are invisible outside the writing checkout. Dispatched workers
return results by value; this session writes both tiers in its own checkout.
