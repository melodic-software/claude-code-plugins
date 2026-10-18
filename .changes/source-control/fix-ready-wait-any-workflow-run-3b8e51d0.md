---
bump: patch
---

### Fixed

- `/source-control:pull-request ready` waits for the push's CI runs and confirms the ready run without a hardcoded `ci.yml`: it counts the head commit's `pull_request` runs from every workflow and stops waiting once that count holds steady across two polls. In a repository with no `ci.yml` the wait always timed out and the draft and ready toggle fired, re-running the ready lanes a second time.
