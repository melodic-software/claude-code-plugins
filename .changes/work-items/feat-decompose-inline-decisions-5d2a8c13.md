---
bump: minor
---

### Changed

- **`/work-items:decompose` item bodies inline each thread's decisions.** The body template gains a `## Decisions` section: each decision the slice rests on, redacted, with its Q/D id, so a body stands on its own in a public tracker. The fill rules still forbid a memory-slice path. The evals gain a case asserting inlined decisions with their Q/D ids and no memory-slice path.
