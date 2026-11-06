---
bump: patch
---

### Changed

- Every pipeline reader of the tracker's human-gated role label (ci-status's holds, the merge queue's early holds, pr-merge, pr-unblock and its dispatcher, the activity runners, report-escalation, report-outcome, the release label holds) reads the `tracker` mapping of the base's `docs/conventions/work-items.yaml` instead of `.work-item-tracker.json`, still from the trusted base or default-branch checkout and still `needs-human` when the file binds none. The issue lanes' lease steps let the work-item tracker seam find the binding in the default-branch checkout. This repository's `.work-item-tracker.json` is removed.
