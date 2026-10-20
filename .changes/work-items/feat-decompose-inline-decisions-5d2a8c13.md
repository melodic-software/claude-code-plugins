---
bump: minor
---

### Changed

- **`/work-items:decompose` item bodies inline each thread's decisions.** The body template gains a `## Decisions` section: each decision the slice rests on, redacted, with its Q/D id, so a body stands on its own in a public tracker. The fill rules still forbid a memory-slice path. Step 1 now reads those decisions from the PLAN.md decisions table and the topic's interview ledger, and a decision with no id in its source is inlined without one. The evals gain a case asserting inlined decisions with their Q/D ids and no memory-slice path.
