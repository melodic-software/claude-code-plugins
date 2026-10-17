---
bump: minor
---

### Added

- The pr-merge lane (`babysit_merge.py --unattended --authority pr-merge`) reads the pr-verify verdict when `merge.require-verifier-verdict` is true: it refuses a pull request without a counted `pass` or `pass-notes` artifact `pr-verify-<pr>-<head-sha>-<verdict>` at its vetted head (`verify:missing`), with a counted `fail` there (`verify:fail`), or with a counted `fail` at any earlier head (`verify:earlier-fail`, for a human), and dequeues a queued entry on the same rules. An artifact counts only when its run is `.github/workflows/pr-verify.yml`, event `workflow_run`, on main, concluded success, in this repository with a head on main; any other is ignored. A dependency manager's pull request is refused before the verdict is read.
