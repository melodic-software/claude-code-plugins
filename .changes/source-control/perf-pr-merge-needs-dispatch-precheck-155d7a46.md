---
bump: minor
---

### Added

- `babysit_postmerge.py --uncovered-since MERGED_AT --branch BRANCH` makes one read of the branch's newest full dispatch run and exits 6 when it was created before MERGED_AT, the point where `--stop-uncovered` would stop. pr-merge's PR-scoped wake runs it first and ends there on 6, before its last-report, carry, lane-records and fresh-check reads.
