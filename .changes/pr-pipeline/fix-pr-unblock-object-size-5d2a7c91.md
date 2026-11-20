---
bump: patch
---

### Fixed

- PR Unblock starts again: `pr-run-activity-read.yml` drops its `workflow_call` descriptions, which GitHub counts in the expanded workflow, so pr-unblock's 15 calls to it stay under the "Maximum object size" limit with the `claude-lanes` environment blocks in place.
