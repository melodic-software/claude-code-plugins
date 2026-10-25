---
bump: patch
---

### Fixed

- The issue lane no longer runs an agent-ready issue that a `blocked_by` issue or pull request still blocks (owner decision Q95). A blocker stops blocking only as admission judges it: a pull request merged in this repository, or an issue closed, for any reason, by a listed human or, in this repository only, a merge; another repository's issue is read there. Admission, work-unblock, the lane's gate and the queued count now share that one rule (`admit.mjs` `blockerDone` and `stillBlocking`).
  - The admit job checks the blockers after the trusted-trigger check. A blocker that still blocks, or blockers it cannot read, skip the run with a notice or warning. The skip takes no model turn, adds no `needs-human`, and leaves `agent-ready` on.
  - work-unblock's sweep never re-fires, strands or hands to a person an agent-ready issue that a blocker still blocks. Once no blocker blocks, it re-fires a run the gate skipped.
  - The same admit step applies admission's provenance rule (`admit.mjs` `untrustedHold`) to a label added by hand. An issue carrying `work-class: untrusted-provenance`, or whose newest removal of it was by neither a listed human nor the lanes App, stops for good with a notice. The sweep never re-fires it and adds no `needs-human`. Labels or events it cannot read skip with a warning, and the sweep retries.
  - The WIP cap's queued count leaves out agent-ready issues that a blocker still blocks. It makes at most 30 blocker reads per check.
  - Files: `.github/workflows/work-resolve-issue.yml`, `.github/scripts/work-resolve-issue/check-blockers.mjs`, `.github/scripts/work-unblock/label-unblocked.mjs`, `.github/actions/check-wip-cap/check-wip-cap.mjs`.
