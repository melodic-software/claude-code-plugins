---
bump: patch
---

### Fixed

- The post-merge check (`babysit_postmerge.py`) skips a full run cancelled with no job on attempt 1, one pr-require-checks.yml's main-dispatch concurrency group replaced before it started: it no longer holds a merge as attribution-pending, asks for its re-run, or serves as the baseline of a later red run. A run cancelled after its jobs started still reads red.
