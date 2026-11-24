---
bump: minor
---

### Added

- `pull-request` monitor: the poll script's watch prints a `PR-VERIFY <pass|pass-notes|fail> <head-sha>` line once for each pr-verify verdict that lands at the PR's current head, read by exact artifact name only where the base branch holds `.github/workflows/pr-verify.yml`; a FAIL line points at the `pr-verify-failed` label and the fail-note review threads. A re-arm snapshot carries the verdicts, so a re-armed watch does not report them again.
- `pull-request` monitor and `status`: `monitor-poll.sh --verdict` reads the verdict at the head once and prints it, `PR-VERIFY none`, or `PR-VERIFY off`; the per-iteration checklist (B3) and the readiness verdict include it.
