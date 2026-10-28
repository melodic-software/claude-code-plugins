---
bump: patch
---

### Security

- The `address-feedback` reply job (`publish-feedback`) and its `report-escalation` now accept a PR head past the reviewed one only when it is the exact commit `apply-feedback-patch` pushed, passed on as the write workflow's new `pushed-commit` output and the trigger gate's new `pushed-commit` input. A GitHub-verified lanes App commit made during the run, but not by that push, no longer passes the gate. The token broker still checks the old rule until it takes the pushed commit too.
