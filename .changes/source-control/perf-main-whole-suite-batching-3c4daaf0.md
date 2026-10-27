---
bump: patch
---

### Fixed

- The post-merge check (`babysit_postmerge.py`) skips a full run cancelled with no job on attempt 1, one pr-require-checks.yml's main-dispatch concurrency group replaced before it started: it no longer holds a merge as attribution-pending, asks for its re-run, or serves as the baseline of a later red run. A run cancelled after its jobs started still reads red.

### Added

- `babysit_postmerge.py --lane-alerted RUN_ID --branch <branch>` exits 0 when pr-merge.yml's post-merge-dispatch on the branch already sent that full run to post-merge-demotion-alert.yml, 1 when not, 3 when unreadable. It counts the `pr-merge-alerted-<id>` record only from a sender the dispatch and re-run records' rule accepts (`_lane_sender`), so a same-name artifact from any other run is no record.
