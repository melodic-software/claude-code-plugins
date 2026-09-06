# Design resolution: drift-delta-routine

- outcome: early-exit
- tier: C
- date: 2026-09-06
- reason: The change is a markdown contract addition inside one plugin (a new routine
  catalog leaf, a catalog row, a regenerated emission, changelog, version). No new type,
  no interface, no package topology change. The one structural constraint, the leaf's
  `## Prerequisites` shape the generator parses, is an existing contract the plan copies
  from `tech-debt-sweep.md`, not a design decision.
