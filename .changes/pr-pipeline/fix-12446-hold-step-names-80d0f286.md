---
bump: patch
---

### Changed

- ci-status's merge-holds step is now `Fail a lanes App pull request on kill switch, hold path, verifier or veto`. pr-verify's held-run check still takes the earlier name, which runs from before the rename report.
- The merge-holds verdict line is now `no member veto and no hold path.`. ci-status still takes the earlier line, for a run whose module comes from a main tip behind its workflow.

### Removed

- `pr-feedback-dispatch.yml` no longer re-runs ci-status when a pr-unblock run completes: ci-status reads no `pr-unblock/*` status.

### Fixed

- The loop-lane contract no longer says a pull request comment is never a hold: a member's veto comment holds a lanes App pull request.
- The "Not settled yet" note on holds gives the seven places as the 2026-11-01 count, not today's.
