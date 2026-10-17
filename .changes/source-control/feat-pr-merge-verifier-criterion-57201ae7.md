---
bump: minor
---

### Changed

- The pr-merge lane (`babysit_merge.py --unattended --authority pr-merge`) treats every pull request the lanes App opened, with exactly one closing issue in this repository and no denied path, as class C2 and reads no `work-class:` label or label history; the risk score's diff-derived C2 checks still apply. With a rung above off it refuses `verifier-verdict-not-required` unless `merge.require-verifier-verdict` is true, since the pr-verify verdict is now its merge criterion. `recheck_lane_class` becomes `recheck_lane_issue`: right before the enqueue the closing issue must still be the one the eligibility read found (`closing-issue-changed:<was>><now>` otherwise), and a removed class label no longer refuses. Dependabot pull requests are unchanged and need no verdict.
