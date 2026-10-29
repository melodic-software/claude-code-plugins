---
bump: patch
---

### Fixed

- Intake admission (`admit.mjs`) holds an issue for a person when a body line outside a code
  fence opens with `Hold:`, read in any case and with invisible characters dropped. work-unblock's
  sweep leaves such an issue unlabeled too. Admission also holds an issue the lanes App filed
  unless it is a trusted size-split sub-issue.
- A decision comment on an issue that carries `needs-human` no longer removes that label or
  dispatches intake (`reenter.mjs`). A listed human's removal of `needs-human` now sends the
  issue back to intake from `status: needs-decision` too.
- Parallel apply-verdict runs cannot admit past the issue lane's queued cap. Admission adds
  `admission-deferred` as a reservation before it reads the room. Another run's reservation from
  the last 15 minutes takes one place of the room when its issue is older or it reserved no more
  than 5 seconds later. check-wip-cap now reads the queued agent-ready issues from the issues API, not search,
  so an issue another run just admitted counts at once. A run that stops partway leaves the issue
  deferred for work-unblock's sweep.
