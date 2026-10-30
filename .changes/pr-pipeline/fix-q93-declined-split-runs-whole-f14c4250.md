---
bump: minor
---

### Changed

- A Size Large issue whose size split the lanes App declined on its current body now runs whole on the issue lane, as a trusted size-split sub-issue does: admission takes it whatever its Size at the next work-unblock sweep, and the issue lane runs it at `models.issue-dimensions.split-child-size`. A decline on an older body version, by another author, or quoted does not count, and an open sub-issue still makes it wait. `admission-rules.json` `size-split` gains `declined` (`run-whole`, the default, or `park`, which keeps it parked), and the decline comment says which applies.
- resolve-config's `split-child` input is now `runs-whole` (env `RUNS_WHOLE`), set by work-resolve-issue's admit job from `admit.mjs` `runsWhole`.
