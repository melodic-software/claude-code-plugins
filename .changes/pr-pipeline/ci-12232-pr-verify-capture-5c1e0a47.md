---
bump: minor
---

### Added

- `pr-verify-capture.yml` drives the app a pull request changes, unattended, once
  `merge.verify-capture.app` is set (unset: it stops with a note). It runs the pull request's
  code in its own workflow, never in a `pr-verify.yml` run, on the same trigger and the same
  in-repo-head gates as the judges, with a read-only token. A reach probe runs before any head
  code and fails the job when a process where the app will run can read pr-verify's key, the
  job token or the runtime token. The key goes to the Claude Code driver alone. The capture
  uploads as `pr-capture-<pr>-<head-sha>` with `merge.verify-capture.retention-days`.
- Each pr-verify judge job finds that capture (`find-capture.mjs`; check-intent waits at most 35
  minutes for it) and downloads it into `pr-verify-data/capture/`. The judge reads it as
  untrusted data, and a missing, unfinished or blocked capture never fails a head. The verdict's
  evidence block reads run-e2e's `e2e-summary.json`.

### Changed

- A pull request body line `Evidence loop: 3/3 cap reached, last NEEDS WORK` in trusted text is
  a `fail`, and the verdict's `local_loop` reads that line as 3.
