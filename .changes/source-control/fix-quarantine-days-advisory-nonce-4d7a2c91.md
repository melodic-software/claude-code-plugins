---
bump: patch
---

### Fixed

- **A merge can no longer lengthen its own quarantine.** The post-merge judge (`babysit_postmerge.py`, `check` and `--judge-run`) takes `merge.quarantine-days` as the smaller of its value at the red run's commit and at the last green full run's commit before it (the default, 7, when there is none), never above 30. A merged change that raises the value no longer keeps an out-of-set suite excused for longer.
- **One suite's output can no longer excuse another failing suite.** The judge credits a `failed ... but is advisory` warning only when it carries the nonce `scripts/run-plugin-tests.sh` prints before any suite block (`Advisory nonce: <16 hex>`). A warning printed inside a suite's block, or carrying any other nonce, excuses nothing, and that suite's failure demotes.
