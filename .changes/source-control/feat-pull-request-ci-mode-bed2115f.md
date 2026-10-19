---
bump: minor
---

### Added

- `/source-control:pull-request ci --ci` is the pr-unblock lane's unattended fix for a pull request's failing checks. It reads the runner's context file as data, reproduces each failing check with the repository's own command, fixes the cause, reruns the check, and leaves the fix uncommitted for the runner to turn into a patch. It never weakens a test, suppresses a lint rule or edits a file under `.github/`; a check it cannot fix is reported with a named reason (`not-reproducible`, `flaky`, `protected-path`, `weaken-required` or `unfixed`).
