---
bump: patch
---

### Fixed

- A pr-verify pass verdict's PR-scoped pr-merge run (`pr-merge: arm #<n>`) no longer skips when the last sweep's post-merge report does not stand. It removes that report, runs the post-merge check fresh on its own read-only token, and arms only when the check passes (exit 0 or 5) and `settle --idle-tick` keeps the fresh report. That is every gate the sweep applies, plus the idle tick on the fresh report, because the wake starts no full run or re-run. A wake no longer waits up to 30 minutes for the sweep, and each refused wake costs more `GITHUB_TOKEN` calls, as the pull request states. The `pr-merge-wake` notice now reports which report the room came from (`report=last`, `fresh` or `none`) and why the idle tick refused a fresh report, and a run the lanes kill switch stops says so instead of "the who step stopped it".
