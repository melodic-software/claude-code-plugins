# Topic-docs placement — what this plugin reads and writes

How `/work-items:work-items` actions resolve topic-document paths in a consuming repo. The skill
reads this one document; it bakes no paths of its own.

Implements the topic-docs convention:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>.
The contract owns the tier table, concern-file schema, slug spec, resolution ladder, and lifecycle;
this document binds this plugin's artifacts to it.

## What this plugin writes, per tier

| Artifact | Tier | Location |
|---|---|---|
| `work-items-checklist.md` (per-topic action ledger) | Memory | `.work/<slug>/` — never committed |
| Ad-hoc drafts and notes (e.g. an unfiled item draft from `add`'s authorization gate) | Memory | `.work/<slug>/` — never committed |
| Tracker projections (items, labels, dependency edges, comments) | Ticket edge | the work-item-tracker seam — never files |

The memory root is configurable via the concern file's `memory_dir` key. This plugin never writes
the contract tier (`docs/topics/<slug>/`).

## What this plugin reads — the three-location plan lookup

`decompose` (and any action sourcing a plan or PRD) resolves `PLAN.md` / `PRD.md` in this order;
the first location holding the document wins, and one topic never spans locations:

1. `docs/topics/<slug>/PLAN.md` — the contract slice on the task branch (default,
   `contract_tier: branch`).
2. `.work/<slug>/PLAN.md` — the memory tier, when the concern file sets `contract_tier: local`
   (solo/offline mode).
3. `.claude/notes/<slug>/PLAN.md` — legacy location, deprecation grace only: read it, emit the
   deprecation notice naming the owning plugin's setup skill as the guarded migration path.

Roots 1 and 2 are configurable via the concern file's `contract_dir` / `memory_dir` keys.

**Sunset:** rung 3 (the legacy dual-read) is removed at this plugin's next major version, no sooner
than one minor release after its deprecation notice shipped.

## Slug and guards

- `<slug>` derives per the contract's slug spec (explicit argument → Brief/PRD topic → current
  branch name; kebab-case `[a-z0-9-]`, ≤ 40 chars). The same slug names the topic in both tiers.
- **Self-ignore guard:** the session's first memory-tier write verifies the resolved memory root
  contains a `.gitignore` with `*`, creating it (announced) when absent — fresh clones heal on
  first write. Once per session, per the contract.
- No skill in this plugin ever edits the consumer's root `.gitignore`.
- Configuration resolves through the convention's resolution order (`.claude/topic-docs.yaml`
  concern file first, documented defaults last).
