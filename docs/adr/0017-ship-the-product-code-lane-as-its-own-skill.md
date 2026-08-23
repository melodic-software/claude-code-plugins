# Ship the product-code lane as its own skill, not an argument of `overengineering:audit`

- Status: accepted
- Date: 2026-08-23

## Context

The `overengineering` plugin V1 (#2961) shipped one lane: the enforcement surface. Its scrutiny
method was deliberately written lane-reusable at the plugin level
(`plugins/overengineering/context/scrutiny-method.md`), whose "Lane binding" section states that
§§1-12 are lane-independent and that a lane supplies four things: the item inventory, the layer
vocabulary and discovery probes, the evidence sources mapped onto the §2 tiers, and the lane's
protected-class defaults.

A second lane covering code-level overengineering in product code (speculative abstraction, unearned
indirection, premature generality) was judged valuable during the `overengineering-detection-skill`
interview and deferred to #2897, which left three questions open: the lane's walker and evidence
sources, its boundary against existing owners, and whether it ships as a third skill or as an
argument-selected lane of `overengineering:audit`.

The first two are answered in `plugins/overengineering/context/product-code-lane.md`. This ADR
records the third.

## Decision

**The product-code lane ships as its own skill.** `overengineering:audit` stays bound to the
enforcement surface, and its `argument-hint` layer vocabulary is not extended to cover product code.

Four reasons, in the order they carry weight:

- **Skill descriptions are the routing surface, and they are budgeted.** Claude Code drops skill
  descriptions from the listing least-invoked-first, so a description that dilutes its trigger
  vocabulary makes the skill harder to match, which makes it less invoked, which drops it sooner.
  `overengineering:audit`'s description is already dense with enforcement-surface vocabulary, and
  this lane's triggers ("is this abstraction earning its keep", "do we need this interface") share
  no keywords with it. Fusing them degrades matching for both lanes. This fleet ships
  `claude-ops:audit-skill-visibility` because this failure mode is real here.
- **The protected classes do not map.** §7's enforcement classes are about guards and their bypass.
  The product-code lane's classes are about changing code that runs: published API surface under a
  compatibility commitment, serialization and wire formats, concurrency primitives, error-containment
  boundaries, and testability seams. A shared skill would carry two disjoint protected-class sets and
  have to select between them by argument, which is the shape of two skills.
- **Retirement means something different, and costs differently.** Retiring an enforcement mechanism
  removes a check. Retiring an abstraction changes code that runs, so §11's rollback ladder carries
  behavior risk that the enforcement lane's does not, and `realign`'s enforcement-shaped ladder
  (disable, narrow, warn-only, remove) is not the product-code ladder (inline, collapse, narrow,
  delete).
- **§10's YAGNI boundary is load-bearing here rather than a corner case.** Fowler's YAGNI is about
  product code. The out-of-scope list has to be restated in code-level terms, because "delete the
  abstraction" and "delete the safety net" can look alike in a diff.

### The shared machinery is extracted, not forked

The one real argument for fusion is that both lanes share walk orchestration. That is solved by
extraction, which is what this plugin already did once for the method itself:

When the lane is implemented, the lane-independent parts of
`plugins/overengineering/skills/audit/context/surface-walk.md` (the per-layer loop, the aggregating
container rule under "Granularity", incremental artifact writes, and the closing step) move to the
plugin root alongside `scrutiny-method.md`, and both lanes bind them. The enforcement layers 1-10
stay with `audit`. Neither lane restates the shared parts, per the same no-second-statement rule
`scrutiny-method.md` already enforces.

Until that extraction lands, `product-code-lane.md` points at the enforcement lane's copy rather than
duplicating it, so there is one statement of each rule at every point in the transition.

## Consequences

- `overengineering:audit` keeps its current scope and description. No change to it is required by
  this decision.
- `realign` will need a product-code rollback ladder before the new skill can execute findings, and
  that is the natural next slice after the skill's audit half.
- The boundary against `/simplify`, `code-tidying`, and `architecture:improve` is documented in
  `product-code-lane.md` §6 as three operational handoffs rather than a declaration, so the new
  skill's description can point at it rather than restating it.
