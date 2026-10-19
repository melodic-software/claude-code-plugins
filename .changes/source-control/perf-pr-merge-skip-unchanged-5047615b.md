---
bump: patch
---

### Changed

- `babysit_merge_skip.py` keys each pr-merge candidate on the inputs its refusal can depend on (head,
  `updatedAt`, labels, base SHA, check rollup, reviews and threads, comments, closing issues, verdict
  artifacts, the gate's config and code on the default branch, the rung cap), read with one GraphQL
  query per 20 candidates and the artifact listing the gate's first candidate reuses. `filter` sets
  aside a candidate whose `risk:MED`, `risk:HIGH` or listed `verify:` refusal stands on the same key
  within the `merge.skip-unchanged` limits, never one in the merge queue; `record` stores each
  gated refusal whose gate process left nothing to do. A skip only repeats a refusal. The verdict
  reader gains `Reader.listing()`.
