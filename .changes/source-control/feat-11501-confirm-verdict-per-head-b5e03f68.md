---
bump: minor
---

### Added

- The `ready` report has a confirm verdict line: the `/verification:confirm` verdict recorded for
  the head it flipped, with each `MISSING` or `PARTIAL` item, or that none is recorded for that
  head. The line is advisory, so a `NEEDS WORK` verdict or a missing one never holds the PR in
  draft, and the `verify` gate is unchanged.
