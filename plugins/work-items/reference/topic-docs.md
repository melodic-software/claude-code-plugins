# Topic-docs placement — what this plugin reads and writes

How the work-items skills (`track`, `work`, `triage`, `decompose`, `scan-todos`) resolve topic-document
paths in a consuming repo. The skills read this one document; they bake no paths of their own.

Implements the topic-docs convention:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>.
The contract owns the tier table, concern-file schema, slug spec, resolution ladder, and lifecycle;
this document binds this plugin's artifacts to it.

## What this plugin writes, per tier

| Artifact | Tier | Location (default) |
|---|---|---|
| `work-items-checklist.md` (per-topic action ledger) | Memory | `.work/<slug>/` — never committed |
| Ad-hoc drafts and notes (e.g. an unfiled item draft from `add`'s authorization gate) | Memory | `.work/<slug>/` — never committed |
| Tracker projections (items, labels, dependency edges, comments) | Ticket edge | the work-item-tracker seam — never files |

The memory root is configurable via the concern file's `memory_dir` key. This plugin never writes
the contract tier (`<contract_dir>/<slug>/`).

## What this plugin reads — the tier-selected plan lookup

`/work-items:decompose` (and any skill sourcing a plan or PRD) selects the location from the concern
file's `contract_tier` FIRST, then reads only that tier's slice — one topic never spans locations,
and a stale slice in the other tier never shadows the live one:

- `contract_tier: branch` (the default) → `<contract_dir>/<slug>/PLAN.md` (default `docs/topics/`).
- `contract_tier: local` (solo/offline mode) → `<memory_dir>/<slug>/PLAN.md` (default `.work/`).

Both roots are configurable via the concern file's `contract_dir` / `memory_dir` keys.

## Slug and guards

- `<slug>` derives per the contract's slug spec (explicit argument → Brief/PRD topic → current
  branch name; kebab-case `[a-z0-9-]`, ≤ 40 chars). The same slug names the topic in both tiers.
- **Self-ignore guard:** the session's first memory-tier write verifies the resolved memory root
  contains a `.gitignore` with `*`, creating it (announced) when absent — fresh clones heal on
  first write. Once per session, per the contract.
- No skill in this plugin ever edits the consumer's root `.gitignore`.
- Configuration resolves through the convention's resolution order (`.claude/topic-docs.yaml`
  concern file first, documented defaults last).
