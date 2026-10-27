---
bump: patch
---

### Fixed

- An issue run whose `apply-issue-patch` job failed without giving an escalation reason now hands back as `patch-apply-failed` ("apply-issue-patch failed before it committed or refused the patch"), not as "The run reported done but committed nothing". `work-resolve-issue.yml` sets the reason from the job's result, and the write runner's input check admits it in issue mode.
