# Topic-docs resolution — where architecture artifacts land

How the `improve` skill resolves the destination for its durable per-topic artifact.

Implements the topic-docs convention:
<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/topic-docs/README.md#runtime-guards>.
The contract owns every general rule — tiers, schema, resolution order, slug spec, runtime guards,
no-project-root fallback, non-interactive/forked mode. This document records only this plugin's
deltas.

## What this plugin writes, per tier

| Artifact (writer) | Tier | Location (default) |
|---|---|---|
| `deepening-candidates-<YYYYMMDDTHHMMSSZ>.md` (`/architecture:improve deepening`) | Memory | `.work/<topic-slug>/` — never committed |
| Deepening HTML report (`/architecture:improve deepening`) | Ephemeral | One file per run, created through the platform's temp API; handed back as a path and never deleted before returning |
| `fleet-plan.json` (`/architecture:map-landscape --root`) | Memory | `.work/<topic-slug>/` — never committed |

`fleet-plan.json` is the `repo-fleet-hygiene` collaborator's action plan, written there by that
plugin's audit when `map-landscape` invokes it with `--plan-file`. It is a temp artifact of one run:
`map-landscape` reads `schema_version` and `repositories[]` out of it and nothing downstream reads it
again, so the memory root's self-ignore guard is what keeps a plan naming every repository on the
operator's disk out of git history. It is never copied into the declared `architecture_dir`.

The candidate list is a cross-stage handoff: a planning step consumes its `agreed-shape` entry
(see the deepening playbook's Handoff section). It stays in the memory tier because nothing
downstream *enforces against* it — the agreed shape graduates into planning's own contract-tier
artifacts (`PLAN.md`), which is where enforcement begins.

The HTML report is a human-readable companion that nothing downstream reads again, so it lands in
the contract's ephemeral tier. Its rules are the contract's — one deterministic path, never the
session scratchpad, no delete-before-return because the path is the delivery mechanism, and one
file per run because nothing documented reclaims the temp tree — not a delta of this plugin's.

## Slug derivation

Per the contract's precedence, from this skill's inputs: an explicit scan-focus argument (e.g. a
named module or path) → the current branch name. Form and collision rules are the contract's.

## Guards

The memory root's self-ignore guard applies on first write (verify-or-create `.gitignore` with
`*`, announced). The contract also defines **invalid roots at which the guard does not run**; they
are enumerated in its
[Runtime guards](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/topic-docs/README.md#runtime-guards)
section and deliberately not listed here, so this binding cannot drift from them. Create the topic
slice directory when absent.
