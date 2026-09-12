---
description: "Read-only inventory of a documentation tree's file names against a configured casing rule: proposes a new name per offender, finds every reference to each one, classifies each site by shape (markdown link, backtick path, absolute URL, table cell, prose, bare stem) and by the citing file's tier, refuses any plan that would create a case-only path collision, and writes a rename plan the realign skill consumes one acceptance at a time. Use when: 'audit file names', 'are our doc filenames consistent', 'plan a docs rename', 'which files break the naming rule', 'find every reference to this doc', 'rename the docs tree', 'lower-kebab the docs folder', 'what would a docs rename touch'. Read-only: it renames and edits nothing."
argument-hint: "[audit] [root ...]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/inventory.sh:*)", "Bash(${CLAUDE_SKILL_DIR}/scripts/sweep.sh:*)", "Bash(${CLAUDE_SKILL_DIR}/scripts/emit-findings.sh:*)", "Bash(git branch --show-current:*)", "Bash(git rev-parse:*)", "Bash(git check-ignore:*)", "Read", "Write", "Grep"]
shell: bash
metadata:
  workflow-stage: anytime
  summary: Inventory a doc tree's file names and plan the renames with their references
---

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never
combined into a single invocation:

- Current branch, `git branch --show-current`
- Working tree status (empty = clean), `git status --porcelain | head -20`
- Repository root, `git rev-parse --show-toplevel`

The pipe is the bound and belongs in the command. A read-time cap bounds
nothing: the Bash tool returns the command's complete output into context before
there is anything to decide about.

Treat a failure as an unknown value and carry on.

## Purpose

A documentation tree drifts one file at a time, and by the time anyone notices,
the cost of fixing it is not the renames. It is finding every citation of every
renamed file, deciding which of them may be rewritten, and not corrupting a
generated record or a released changelog entry on the way through.

This skill does the finding and the deciding, and writes the result down. It
renames nothing. `/docs-hygiene:realign-file-names` executes the plan, one
acceptance at a time.

## Read these before presenting anything

| Read | For |
|---|---|
| [`context/tiers.md`](context/tiers.md) | the form table to print before any plan, and why a historical tier keeps its links while a released tier is frozen |
| [`../../context/file-name-findings.md`](../../context/file-name-findings.md) | the artifact's shape, its stable ids, its status arcs, and the re-audit merge |
| [`../../reference/topic-docs.md`](../../reference/topic-docs.md) | where the artifact goes, and the rung order that resolves it |
| [`../../reference/config.md`](../../reference/config.md) | every configuration key, its default, and which layer may supply it |

## Facts before judgment

Three scripts produce the facts. Run them in order and build the plan on what
they emit.

1. **Inventory** the tree:

   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/inventory.sh --root <repo>
   ```

   It emits `OFFENDER`, `COLLISION`, `EXEMPT`, and `SCANNED` rows. A `COLLISION`
   row means the plan would put two paths differing only by case into one tree.
   **Stop there.** Report the pair and the reason, and propose nothing: on a
   case-insensitive checkout the second file overwrites the first, so this is a
   corrupted tree rather than a plan to review.
   *Done when:* a `SCANNED` row is present and the `COLLISION` count is zero.

2. **Sweep** for references, feeding it the offender pairs:

   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/sweep.sh --root <repo> --pairs <pairs.tsv>
   ```

   Each `REF` row carries the citing file, the line, the form, the tier, the
   action, and an excerpt. The actions are `edit`, `report`, `review`, `skip`,
   and `regenerate`; `context/tiers.md` owns what each means.
   *Done when:* a `SITES` row is present and every offender pair appears in at
   least one `REF` row or is reported as having no site at all.

3. **Compose** the plan into the resolved home:

   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/emit-findings.sh --root <repo> \
     --inventory <inv.tsv> --sweep <sweep.tsv> --out <resolved>/file-names.md
   ```

   *Done when:* the script reports the path it wrote and a finding count equal
   to the inventory's offender count.

**Cite the scripts' rows verbatim.** The realign applies the action each site
carries, so a form or a tier you inferred by reading is a guess that edits the
wrong shape. If a site does not correspond to a `REF` row, say so rather than
inventing one.

## Where the artifact goes

Resolve the home through the plugin's topic-docs binding and write under it.
Never compose the documented default's shape yourself: a consumer whose memory
root is configured elsewhere gets a plan the realign never finds, and that
failure reads exactly like "no audit has been run".

If a plan already exists at the resolved home, the emitter merges into it by
finding id and carries every decision forward. Do not delete it to get a clean
run; a declined finding that reappears as pending is a decision the operator
made being asked again.

## Present the result

1. The form table for every tier the plan touched, from `context/tiers.md`.
2. One line per finding, most-cited first: the old and new path, the site count,
   the tier breakdown, and whether a generated file is involved.
3. Every `review` site, individually, with its line and excerpt. These are the
   ambiguous bare stems, and no script can settle them.
4. The artifact's path, and the next step: `/docs-hygiene:realign-file-names`
   with the ids to accept.

Say the count of `report` sites plainly. A maintainer who expected a frozen tier
to change needs to see that it did not.

## Completion criteria

The run is done when the artifact exists at the resolved home, its finding count
equals the inventory's offender count, the tree is byte-identical to how it
started (`git status --porcelain` unchanged), and every `review` site has been
surfaced to the operator rather than folded into a total.

## What this skill does NOT do

- Rename anything, edit any reference, or run any regenerator. It is read-only
  on every file it inspects.
- Re-judge a plan it already wrote. A stale plan is re-audited, not patched.
- Decide whether a `review` site names the file. It escalates them.
- Bump a version, write a changelog entry, or commit.
- Sweep a tree the configuration excludes, or a file a tier freezes.

## Next

`/docs-hygiene:realign-file-names`

## Gotchas

- **A collision refuses the plan, not just one finding.** Two paths differing
  only by case cannot coexist on macOS or Windows checkouts. The whole run stops
  so nobody applies half of it.
- **Existence is asked of the git index, never the filesystem.** On a
  case-insensitive checkout a filesystem test answers for the wrong spelling,
  which would refuse every case-only rename on exactly the platforms the rule
  protects.
- **A `review` site is not a smaller `edit`.** It is a bare stem that is also an
  ordinary word. Rewriting one on a text match is how a rename edits a sentence
  that had nothing to do with the file.
- **A generated record is never text-edited.** Its sites are marked
  `regenerate`, because a substitution that looks right leaves a stale derived
  value no reader would notice.
- **The plan is checkout-local.** It lives in the memory tier, keyed by branch,
  and a sibling worktree never sees it. A decision that must outlive the branch
  goes into the tracked concern file, which the realign offers and never takes.
- **Run it from the tree you mean.** Every script takes `--root`; inside a second
  worktree, pass it, or run from that worktree.
