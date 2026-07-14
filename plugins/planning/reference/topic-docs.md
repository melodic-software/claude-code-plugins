# Topic-docs resolution — where planning artifacts land

How every planning skill resolves the destination for its per-topic artifacts. All pipeline
skills read this one document; none bakes its own placement rules.

Implements the topic-docs convention:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>.
The contract owns every general rule — tiers, schema, resolution order, slug spec, runtime guards,
no-project-root fallback, non-interactive/forked mode, the contract-slice lifecycle with its
redaction bar. This document records only this plugin's deltas.

## What this plugin writes, per tier

| Artifact (writer) | Tier | Location (default) |
|---|---|---|
| `PRD.md` (`/planning:prd`) | Contract | `docs/topics/<topic-slug>/`, committed on the task branch |
| `PLAN.md` — Brief (`/planning:interview`), Plan (`/planning:architect`) | Contract | same slice |
| `design/` — ALL design artifacts, including the `design-threads.md` / `design-resolution.md` gate files (`/planning:design`, gated by `/planning:design-handoff`; gate files must travel with the branch) | Contract | `docs/topics/<topic-slug>/design/` |
| `interview-checklist.md`, `architect-checklist.md` | Memory | `.work/<topic-slug>/` — never committed |
| `baselines/` — machine-bound captures from the architect's baseline step | Memory | `.work/<topic-slug>/baselines/` |
| Opt-in `brainstorm.md` (`/planning:brainstorm` — never a default write) | Memory | `.work/<topic-slug>/` |

`contract_tier: local` moves the contract rows into the memory slice with an identical layout —
the contract's solo/offline mode. Roots are configurable via the concern file's `contract_dir` /
`memory_dir` keys.

## Close-out — the vault seam

`/planning:architect` owns describing the contract-slice close-out. Its promotion step resolves
the concern file's `vault_backend`: `docs` (default) → a guarded, history-preserving `git mv`
into `docs/adr/` / `docs/specs/`; any other value → the backend the consuming repo documents,
degrading to `docs` when that backend's tools are absent.
