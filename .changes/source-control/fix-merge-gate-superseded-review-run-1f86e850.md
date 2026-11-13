---
bump: patch
---

### Fixed

- The unattended merge gate no longer refuses a pull request with `no-lane-job` because an earlier head's review run was superseded: when the head moved while Wait Refine waited, the caller job was skipped and the run reviewed nothing, so the open-findings scan now passes over it. At the pinned head such a run still binds nothing.
