---
bump: minor
---

### Changed

- work-unblock and the hourly triage sweep no longer stop an item for a person outside an intent or security question (owner intent, 2026-10-24):
  - A stranded issue already re-fired on its lane workflow files, or a lane token request that keeps failing, is re-fired again on a backoff (three hours, doubling, at most 24) with one comment edited in place, never `needs-human`.
  - A lanes App PR merged with `Refs:` or closed unmerged takes `status: ready` and `agent-ready` off and adds no `needs-triage`, so the triage sweep sends the issue back to intake, whose fresh `status: ready` re-admits it.
  - A blocker closed by a listed human or a merge in this repository counts whatever its close reason, and another repository's blocker counts once a listed human closed it there (a merge there, or another repository's pull request blocker, never counts).
  - A listed human's open pull request for an issue counts as work running on it, so work-unblock does not re-fire or relabel it.
  - The triage sweep re-dispatches intake for any issue with no `status:` label and no `agent-ready` or person's hold, whatever comments intake left (an issue the lanes App opened included), and for a born-triaged issue in `status: ready` that nothing admitted. After two dispatches in one triage cycle (a work-unblock hand-back starts a new one) it labels the issue `needs-triage` and says so in its own comment on the issue, instead of filing a new issue, and later passes skip that issue unread while it carries `needs-triage`.
  - Admission on a blocker's close takes the issues it would label oldest opened first (owner Q95) (`.github/scripts/work-unblock/label-unblocked.mjs`, `.github/scripts/maintenance-audit-lane-runs/triage-sweep.mjs`).
