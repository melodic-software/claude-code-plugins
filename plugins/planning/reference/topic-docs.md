# Topic-docs resolution — where planning artifacts land

How every planning skill resolves the destination for its per-topic artifacts. All pipeline
skills read this one document; none bakes its own placement rules.

Implements the topic-docs convention:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>.
The contract owns every general rule — tiers, schema, resolution order, slug spec, runtime guards,
no-project-root fallback, non-interactive/forked mode, the contract-slice lifecycle with its
redaction bar. This document records only this plugin's deltas.

The sibling `artifact-protocol.md` defines the shared lifecycle artifact names and producer/consumer
behavior; this binding and topic-docs remain authoritative for their placement.

## What this plugin writes, per tier

| Artifact (writer) | Tier | Location (default) |
|---|---|---|
| `PRD.md` (`/planning:prd`) | Contract | `docs/topics/<topic-slug>/`, committed on the task branch |
| `PLAN.md` — Brief (`/planning:interview`), Plan (`/planning:plan`) | Contract | same slice |
| `design/` — ALL design artifacts, including the `design-threads.md` / `design-resolution.md` gate files (`/planning:design`, gated by `/planning:design-handoff`; gate files must travel with the branch) | Contract | `docs/topics/<topic-slug>/design/` |
| `interview-checklist.md`, `plan-checklist.md` | Memory | `.work/<topic-slug>/` — never committed |
| `baselines/` — machine-bound captures from the plan skill's baseline step | Memory | `.work/<topic-slug>/baselines/` |
| Opt-in `brainstorm.md` (`/planning:brainstorm` — never a default write) | Memory | `.work/<topic-slug>/` |

`contract_tier: local` moves the contract rows into the memory slice with an identical layout —
the contract's solo/offline mode. Roots are configurable via the concern file's `contract_dir` /
`memory_dir` keys.

Baselines are machine-bound memory-tier captures, invisible outside the writing checkout: per the
contract's pointer discipline (≥ 2.0.0), `PLAN.md` records **distilled baseline values only** and
never cites a memory-slice capture path. Checklists are the stage-ledger kind the contract's
`.worktreeinclude` template carries into new worktrees where the consuming repo materializes it.

## Close-out — the vault seam

`/planning:plan` owns describing the contract-slice close-out. Its promotion step resolves
the concern file's `vault_backend`: `docs` (default) → a guarded, history-preserving `git mv`
into `docs/adr/` / `docs/specs/`; an enabled non-`docs` value → the backend the consuming repo
documents, degrading to `docs` when that backend's tools are absent.

`gitbook` is reserved but **not enabled** as a writable backend. Preserve the key when it already
exists, report that it is deferred, and promote durable content to `docs`; never call GitBook's
API/MCP write operations or configure Git Sync as a planning close-out action. A consumer may
publish a mirror only through separately reviewed automation that keeps git authoritative. This is
an explicit repository policy because GitBook documents both a writable API and a bidirectional Git
Sync product; neither is a safe implicit fallback:

- <https://gitbook.com/docs/developers/gitbook-api/quickstart>
- <https://gitbook.com/docs/developers/gitbook-api/api-reference>
- <https://gitbook.com/docs/getting-started/git-sync>
- <https://github.com/melodic-software/claude-code-plugins/blob/main/docs/adr/0001-defer-gitbook-as-knowledge-vault-backend.md>
