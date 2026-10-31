---
bump: patch
---

### Fixed

- A `pr-unblock.yml` or `pr-refine.yml` run sent by a dispatcher on an older copy of its file ends green before any model turn, with no check and no stop, and the next dispatcher sends the head again. The broker refused such a run's write tokens as `workflow-modified` only after the model had spent its turns.
- `fix-ci-dispatch.mjs` retries a head whose `pr-unblock / apply-patch` failed on a `lane-token-denied` refusal, under the same caps as a stopped run, in place of skipping it as handled.
- `report-escalation.sh clear` annotates a refused statuses read with `::error::` and gh's message and fails, in place of dying in jq at exit code 5 with no annotation.
