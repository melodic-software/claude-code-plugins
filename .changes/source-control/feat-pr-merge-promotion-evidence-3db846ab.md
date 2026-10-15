---
bump: minor
---

### Added

- **The pr-merge lane gates on promotion evidence.** `babysit_merge.py --authority pr-merge` takes
  `--lane-promotion-evidence` (the JSON `resolve-promotion-evidence.mjs --inline` printed once for
  the run) and `--lane-promotion-window-start`. `read_promotion_inline` reads it and a pull request
  merges only when its class's cell (`C2-auto-merge` or `C3-auto-merge`) is effective `promoted`
  with no `failClosedReason`. No JSON, a fail-closed reason, an unpromoted or missing cell, or a
  demotion record newer than the evidence refuses as `promotion-unqualified:<reason>`, reported in
  report-only mode too. `babysit_merge_policy.py lane-window OWNER/REPO IDENTITY` prints whether a
  demotion record holds and the window start the workflow passes to the check.
