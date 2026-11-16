---
bump: patch
---

### Changed

- The babysit merge gate counts a pr-verify pass whose linked issue is the upstream-drift
  workflow's (github-actions[bot] wrote it and nobody else last edited it, with that workflow's
  title and hex-pin lead line) as a trusted spec when the pull request's changed files, base to
  head, only modify the default branch's `docs/upstream` pages pinned to that upstream, as
  pr-verify does. The gate reads each github-actions issue once for this rule and the
  recurring-schedule rule.
