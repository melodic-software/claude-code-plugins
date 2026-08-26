# Merge findings across producers, and mark consumption explicitly

- Status: accepted
- Date: 2026-08-15

## Context

`review:fanout`'s findings file is a documented stable contract —
`plugins/review/reference/findings-file-shape.md` titles the section "Findings-file shape
(stable contract — the fix action consumes it)". The fix action locates its input **purely by
frontmatter**, never by provenance (`context/fix-pass-mode.md:7`): the newest `*.md` declaring
`type: review-findings` whose `branch:` matches exactly. Nothing authenticates the writer.

That is not an oversight, and it is the cheapest wiring path in the fleet: any component of any
shape — skill, script, hook, agent — that writes a conforming file reaches the apply relay without a
single edit to fanout. It matters because the fleet's gap is **detectors, not apply capability**.
`mutation-testing:audit`, the best deterministic detector present, reaches no relay today only
because fanout dispatches agents and it is a skill.

The contract holds while fanout is the only producer, because its newest file is then the complete
picture. **A second producer breaks that invariant silently.** `fix-pass-mode.md:3` consumes "the
newest persisted findings file"; a grep of the whole fanout tree finds no merge, union, or
multi-file handling. Two conforming producers on one branch means the later timestamp wins and the
earlier producer's findings are never applied — no error, no warning, and the run reports success.
A detector running after a full review would shadow the entire review.

This is the green-with-hidden-findings class that `docs/conventions/liveness-assertion/README.md:58`
exists to prevent, and it fails silently rather than loudly — which is why it is decided before the
second producer ships rather than after.

## Decision 1 — the consumer merges; it does not pick a winner

The fix action consumes the **set** of conforming files for the exact current branch, not the newest
one. Three options were weighed:

- **One writer per directory, plus a merge step.** Rejected: nothing merges today and the merge
  component would have no owner.
- **A detector appends into fanout's file.** Rejected: needs a write-ordering and locking convention
  that does not exist.
- **Merge inside the fix action.** Chosen: the contract's owner extends its own consumer, adding no
  new surface and no new coordination primitive.

Coverage fields are **unioned, not picked**. `findings-file-shape.md` declares `tier`, `## By dimension`,
`## Unparsed`, and `## Surfaces` required "to keep the report honest about coverage". Reporting one
producer's `## Surfaces` line would hide a surface that ran and returned nothing — moving the
hidden-findings failure up one layer instead of closing it. Each consumed file's `tier:` is reported
rather than one winning, and the plan header names the consumed file set.

## Decision 2 — dedup is presence-only, deliberately narrower than Stage 3

Cross-producer dedup collapses rows sharing an identical `Location` **and** identical `Finding` text.
Everything else stays a distinct row with its producer named in `Surface(s)`.

The tempting key is the existing one: normalized path plus a ±3-line bucket. It is unavailable.
`findings-normalization.md:77` places dedup at "Stage 3 Sonnet (semantic merge)", and the fix action
runs no LLM stage. Worse, adopting the bucket without the semantics inverts the pipeline's own rule
(`:66`): "**Minimize FALSE-MERGE over FALSE-SPLIT** — a false merge silently drops a real issue…
When in doubt, do NOT merge." Two distinct defects at `foo.ts:42` and `foo.ts:44` would merge, and
because the fix action applies one `Action` per row and fences each fix to its own file
(`fix-pass-mode.md:56`), one producer's remediation would be silently discarded — reintroducing,
inside the fix, exactly the failure this record closes.

A false split adds noise. A false merge drops a finding. The direction is chosen, not defaulted.

## Decision 3 — the applied-plan record becomes a consumption ledger

Bounding the merge set by timestamp does not work. `fix-pass-mode.md:76` writes the
`type: fix-pass-record` **only** under `--yes` in a non-interactive session — "Interactive and
headless-stop paths write no record". The dominant path writes none, so a timestamp bound anchored on
it is a no-op there and the merge set grows without limit, re-injecting findings that `:95`'s
**required** post-fix re-review has already resolved.

So the record is written on **every** apply path, its `source-findings:` carries the full consumed
set, and the merge set excludes every file already named by a record whose own `branch:` matches
exactly. The branch filter binds both sides: the directory slug is lossy by design, which is why
`:7` calls the frontmatter check load-bearing, and an unfiltered record from a slug-collided branch
would silently truncate the set.

The record's original purpose — an after-the-fact review surface for an apply nobody watched —
becomes additive rather than defining.

## Consequences

- **A detector needs zero fanout edits.** Writing a conforming file is the whole integration. The
  format-only path was validated empirically before this record: a hand-written non-fanout file
  passed the locator, the frontmatter gate, the exact-branch check, and the table parse, including
  the cell-escaping rule.
- **Two producers no longer shadow each other**, which is the property that makes a second detector
  shippable at all.
- **Duplicate rows are possible and accepted.** Presence-only matching splits where a semantic key
  would merge. That is the chosen direction, not an unhandled case.
- **The single-producer case is unchanged byte-for-byte**, and an empty set keeps the existing clean
  STOP path. Those are the migration's safety properties and each is pinned by a fixture.
- **Interactive applies now write a record.** Consumers who read `.work/reviews/<branch-slug>/` will
  see records where previously only headless `--yes` runs produced them.
- **Consumption is per file, not per row.** The ledger's key is the `source-findings:` file name, so
  the granularity follows from Decision 3: a file whose rows were partly surfaced instead of applied,
  or narrowed by the operator at the interactive gate, is marked consumed in full and those rows do
  not survive inside it. Recoverability therefore rests on the record body naming every deferred row
  **with the source file it came from** — an obligation this decision places on the record format,
  not a property the record already had. Recovery re-runs that row's OWN producer: re-running
  `review:fanout` regenerates fanout's rows and nothing else, and a row from another producer returns
  only when that producer runs again. Either way the regenerated rows arrive as a NEW findings file
  that enters the next merge set as a fresh candidate.
- **Re-opens if** the fix action gains an LLM normalization stage — a semantic key would then be
  computable and the narrower one could be revisited. It does not re-open on a request for
  cross-branch consumption: never scanning another branch's findings is a separate fence and is not
  in scope here.
