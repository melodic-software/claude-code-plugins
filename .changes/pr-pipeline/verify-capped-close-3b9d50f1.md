---
bump: patch
---

### Fixed

- A lanes App pull request at `merge.max-verify-fails` (`verify:repeated-fail`) or too old to judge
  (`verify:too-old`) no longer sits unarmed with no signal, and gets no person's label. The pr-merge
  lane (`enable-auto-merge.mjs` through the reader's `capped-close` command, or the gate under
  `merge.lane-prs: gate`) closes it for a fresh attempt at its issue. It posts a
  `<!-- verify-capped-close -->` record quoting each FAILed head's verdict findings on the pull
  request and its issue, then takes `agent-ready` off and puts it back, which starts the fresh
  attempt, before the close; an issue that did not carry `agent-ready` is recorded and not
  restarted. It leaves open a pull request whose issue link the arm path refuses
  or whose issue carries an issue hold label. New `merge.verify-cap-attempts` (default 1) bounds the fresh attempts per issue; past
  it the issue is parked at `status: confirmed`.
- The cross-pull-request FAIL cap leaves out a pull request the lanes App's capped-close record
  names once it is closed, so a fresh attempt starts its own count; only the oldest
  `merge.verify-cap-attempts` attempt records per issue count. A record anyone else wrote or edited
  excuses nothing, and a pull request the close leaves open keeps the lane's refusal note and
  `pr-merge/unarmed` status.
- A pull request reopened after its capped-close record stays open, a rerun after a failed close
  toggles no issue label again unless the run that wrote the record stopped before taking
  `agent-ready` off, the gate path leaves open a pull request a hold label, body hold, member's
  blocking comment or failed read holds (read as never enqueued) or whose human-gated label is
  unreadable, and findings come only from runs of verified origin.
- `label-unblocked.mjs` hands no issue to triage for a lane pull request closed at the cap whose
  record names an attempt, and
  `write-issue.mjs` passes the capped-close record to the next attempt as
  `author_kind: verify-findings`, the only other lanes App comment it keeps.
- `pr-feedback-dispatch.yml` and `pr-unblock-dispatch.yml` start no address-feedback or fix-ci
  round, and post nothing, on a pull request the gate's reader refuses `verify:repeated-fail`
  (`.github/scripts/pr-unblock/verify-cap.mjs`, with each dispatcher job's existing read token).
  The same goes for `verify:unreadable` from another pull request's unreadable FAIL run for the same
  issue, which may hide the cap; that one is read again next run.
