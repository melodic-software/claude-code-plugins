---
bump: patch
---

### Changed

- `clear-escalations.mjs` `LANE_CAUSES.verdict` adds `verify:repeated-fail` and `verify:too-old`, so under `merge.lane-prs: native` a `needs-human` label `enable-auto-merge` placed for either comes off at its head (`refusal-cleared`) once the reader names only lane causes there. `lane-causes-person-codes.test.mjs` also pins `LANE_CAUSES.verdict` against `babysit_verify_evidence.NEEDS_HUMAN`.
