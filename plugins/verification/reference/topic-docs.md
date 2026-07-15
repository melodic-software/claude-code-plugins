# Topic-docs placement — where this plugin's artifacts land

How `/verification:confirm` and `/verification:measure` resolve where generated documents land in a
consuming repo. These skills read this one document; neither bakes its own paths.

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
| Verification manifest (distilled, `verified_at_sha`-keyed; meets the contract's redaction bar) — written by `/verification:confirm` | Contract | `docs/topics/<slug>/verification/` |
| Baselines (machine-bound measurements) — written by `/verification:measure` | Memory | `.work/<slug>/baselines/` — never committed |
| Raw verification captures | Memory | `.work/<slug>/scratch/` |

`contract_tier: local` moves the contract row into the memory slice with an identical layout —
the contract's solo/offline mode. Roots are configurable via the concern file's `contract_dir` /
`memory_dir` keys.

`/verification:confirm` reads the contract-tier `PLAN.md` (produced upstream) for intent; when a plan
states a measurable goal, `/verification:measure` records its baseline values + target into that same
`PLAN.md`. The plan artifact itself is owned by the `implementation` / planning stages, not written here.
