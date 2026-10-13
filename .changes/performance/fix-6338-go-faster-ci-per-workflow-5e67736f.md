---
bump: patch
---

### Fixed

- go-faster: the ci-cd, gates and tests numbers no longer mix workflows and fast failures. `findings.py ci-timing` groups the runs it lists by workflow and times only each workflow's newest successful runs. It reports each workflow apart under `workflows`, with its outcome counts, re-runs, queue wait, run length, slowest step and test steps. The sweeper records one finding per workflow, naming the workflow and that the runs were successful ones, and says when no listed run succeeded.
