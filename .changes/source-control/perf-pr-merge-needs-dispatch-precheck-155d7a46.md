---
bump: minor
---

### Added

- `babysit_postmerge.py --uncovered-at LANE_SHA --branch BRANCH` makes one read of the branch's newest full dispatch run and exits 6 when its head commit does not contain LANE_SHA (ancestry read from a local full-history clone; a head commit no clone holds counts as covered), the point where `--stop-uncovered` would stop. pr-merge's PR-scoped wake runs it first and ends there on 6, before its last-report, carry, lane-records and fresh-check reads.
