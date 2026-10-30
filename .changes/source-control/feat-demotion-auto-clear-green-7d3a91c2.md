---
bump: minor
---

### Changed

- **A red-main demotion record clears once main is green at a later commit.** `read_demotion` no longer holds the rung off on a `schedule` or `dispatch` demotion record that no non-human edited, open or not, when a green `pr-require-checks` run on main (attempt 1, a schedule or a `github-actions[bot]` dispatch) was created after the record at a commit ahead of the record's SHA and on main's history. The earliest such run since the record, read in full, becomes the post-merge floor, so newer runs never move it. Canary and read-back records still clear only by a human close, and any failed read keeps the record holding (#11262).
