---
bump: minor
---

### Added

- **`babysit_merge.py --unattended --authority pr-merge`, the pr-merge lane's gate.** It needs
  `merge.authority: pr-merge` and `merge.agent-identity` at the base, reads its own enabling
  commit for the post-merge floor, and replaces local eligibility with the lane's: a
  `work-class: mechanical` label the lane identity's App applied (the owner account's and other
  bots' label events are ignored; any class label can only make the class stricter) on a diff off
  `merge.diff-check.denied-paths`. No promotion evidence is read; the class is read again before
  the enqueue. While `merge.report-only` is true, `--merge` runs as a check that writes nothing.
