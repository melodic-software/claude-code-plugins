---
bump: patch
---

### Fixed

- address-feedback can now revert an executable bit the pull request itself added, so such a
  finding no longer escalates `feedback-uncertain`. The review-threads skill may run `chmod -x`,
  and its patch carries the mode. apply-patch's `review-threads` row refuses any new file at
  mode `100755` or a change to that mode (the new optional `new-exec-bit` refusal). Its new
  `pr-mode-revert` content rule admits a mode change only back to the mode the path has at the
  merge base of the PR head and its base, or to `100644` for a file the PR added, read through
  the GitHub API, with no workflow change.
  The refusal stays off the other rows, so `ci-context` and the `issue` row's `script-exec-bit`
  still set script bits, and `babysit_risk.py` still rates a mode change `high-path`.
