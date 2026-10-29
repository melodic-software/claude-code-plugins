---
bump: minor
---

### Changed

- A new `skip-reason`, `kill-switch`: a lanes kill switch stopped the run. Every lane's gate stop by
  its own kill-switch step now posts neutral `kill-switch` instead of `prerequisite-missing`
  (`report-check-run`'s `gate-skip-reasons.json`), in every lane check it posts.

### Fixed

- A pr-unblock or pr-refine write job that the token broker refuses with reason `kill-switch` (a
  switch turned on after the run's own kill-switch step read it) no longer ends red.
  `pr-run-activity-write.yml` now passes `kill-switch-ok` on a pull request run, so the token step
  ends green with no token, every later step skips, and the check is neutral `kill-switch`. An
  issue run (work-resolve-issue) stays red, since work-unblock re-fires its issue from the failed
  mint step. Before, a reply job stopped this way ended `feedback-publish-failed`, routed to a
  failing status.

- The pr-unblock dispatchers dispatch a head again once the kill switch lifts. A `kill-switch`
  check never handles a head (`limit-stop.mjs` `killSwitchStop`), and on a push, reply or verdict
  job's check it releases the head's earlier activity checks as a lane stop does: in
  `stopRelease` (resolve-conflicts), the address-feedback reply releases and half-hourly sweep,
  the review-dependency verdict release, and fix-ci, where it spends no restart. Such stops count
  toward `limits.limit-stops-per-head` (`SWEEP_HEAD_CAP` for address-feedback), so a switch that
  keeps flipping mid-run still ends the head. Before, a head whose activity check had run stayed
  handled until a new push.
