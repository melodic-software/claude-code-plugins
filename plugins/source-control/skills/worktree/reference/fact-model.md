# Worktree fact model stays re-derived

Recorded park for
[#3422](https://github.com/melodic-software/claude-code-plugins/issues/3422),
a deepening candidate that would hoist "what git knows about a worktree"
(enumeration, lock reason, risk) into one fact-record producer.

## Decision

**Park. Do not hoist.** Porcelain parse, lock-reason encode/decode, and the
15-column TSV `-` invariant stay re-derived in the scripts and restated in
prose.

- **Option A (taken):** no unpaid hoist. `landed-work.sh` and
  `worktree-claim.sh` keep their own `git worktree list --porcelain` parses.
  The lock reason stays a free-text string. The TSV non-empty invariant stays
  per-field `${...:--}` (with the head slice applied before the fallback).
  The four prose surfaces keep specifying the parse.
- **Option B (declined):** one fact-record producer (one porcelain parse, one
  lock-reason codec, one row schema with the `-` invariant held structurally)
  consumed by the scripts, with prose pointing at it.

**Claim:** source-control has no owning module for the worktree fact model.
Producer and consumers agree by convention. A fact-record hoist is unpaid.
**Basis:** origin/main as of this record. `scripts/landed-work.sh` parses
`git worktree list --porcelain -z` and emits a 15-column TSV through one
`printf` of 15 `${...:--}` expansions (`path` through `reason`).
`scripts/worktree-claim.sh` parses porcelain independently. The lock reason
is written by `worktree-create.sh` and `worktree-claim.sh` and read by claim
check-enter. Prose re-specifies the parse in `context/status.md` (fields),
`context/cleanup.md` (locked / prunable), `context/audit.md` (stale metadata
and claim liveness), and `SKILL.md` (status / cleanup scans). #3371 / #3403
(48bb5fa4b) is the worked failure: `${T_HEAD[$idx]:0:12}` sliced before the
fallback, shifting `risk` and `reason` a column left on notgit and bare-hub
rows. `worktree-root-doctor.sh` is not a third porcelain parser.
**As of:** 2026-09-28.
**Recheck:** a maintainer funds one porcelain parse and one lock-reason codec
consumed by the scripts, with the TSV non-empty invariant held structurally
so a new column cannot repeat #3371, and the prose surfaces point at that
producer instead of specifying a manual parse.

## Rationale

- The TSV `-` contract is already documented next to the `printf` that holds
  it. A structural holder would have to emit the same 15 columns for every
  existing consumer (`status`, `cleanup`, `audit`) without shifting `risk` /
  `reason`.
- Lock-reason encode/decode is a session-identity ladder with five exit codes
  on check-enter. Folding that into a generic fact record is the unpaid
  design.
- The issue is `work-class: structural` and `needs-human`.

## Revisit when

- A maintainer funds the producer and names the first consumer to migrate, or
- a new column or lock-reason field has to be patched in more than one script
  at once again.

## Prior requests

- #3422 (2026-09-28): deepening candidate; Option A recorded here.
