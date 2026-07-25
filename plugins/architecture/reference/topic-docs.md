# Topic-docs resolution — where architecture artifacts land

How the `improve` skill resolves the destination for its durable per-topic artifact.

Implements the topic-docs convention:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>.
The contract owns every general rule — tiers, schema, resolution order, slug spec, runtime guards,
no-project-root fallback, non-interactive/forked mode. This document records only this plugin's
deltas.

## What this plugin writes, per tier

| Artifact (writer) | Tier | Location (default) |
|---|---|---|
| `deepening-candidates-<YYYYMMDDTHHMMSSZ>.md` (`/architecture:improve deepening`) | Memory | `.work/<topic-slug>/` — never committed |

The candidate list is a cross-stage handoff: a planning step consumes its `agreed-shape` entry
(see the deepening playbook's Handoff section). It stays in the memory tier because nothing
downstream *enforces against* it — the agreed shape graduates into planning's own contract-tier
artifacts (`PLAN.md`), which is where enforcement begins.

The HTML report is a human-readable companion written to a secure temp file — deliberately
ephemeral, outside this convention.

## Slug derivation

Per the contract's precedence, from this skill's inputs: an explicit scan-focus argument (e.g. a
named module or path) → the current branch name. Form and collision rules are the contract's.

## Guards

The memory root's self-ignore guard applies on first write (verify-or-create `.gitignore` with
`*`, announced). Create the topic slice directory when absent.
