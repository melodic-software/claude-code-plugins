---
bump: patch
---

### Fixed

- A pr-merge or intake-triage run that the token broker refuses with reason `kill-switch` no longer
  ends red. The lane breaker turns the repository kill switch on after a queued run has read its
  variables, so the run's own kill-switch check passes and only the broker's live read stops it.
  `request-lane-token` takes a new `kill-switch-ok` input (`token` mode only): on that 403 it ends
  green with a `lane-token-stopped` notice, no token and `skip-reason` `kill-switch`. Every step in
  pr-merge's `merge` and `enable-auto-merge` jobs and intake-triage's `apply-verdict` and
  `apply-refinement` jobs that uses the token already runs only when the token is set, and
  intake-triage's `refine-select` now skips on apply-verdict's new `stopped` output. Any other
  denial, and every caller without the input, stays red; work-resolve-issue stays red because
  work-unblock re-fires its issue from the failed mint step. `version` stays 2.

- pr-merge's `enable-auto-merge` no longer queues a lanes App pull request whose head a pr-unblock
  lane stopped. ci-status's merge-queue run fails a head whose newest `pr-unblock/*` status by
  github-actions[bot] is `failure` or `error`, but only after every lane leg ran, and the queue then
  ejected it. The rule now lives in `merge-holds.mjs` (`unblockStops`, `readStatuses`): a stopped
  head, or one whose statuses do not read, is left unarmed (an armed one is disarmed), and each
  such skip gets a line in the run summary.

- pr-merge's `enable-auto-merge` takes `needs-human` off a lanes App pull request itself when the
  lane's newest refusal at the head names only hold paths and a person on the trusted-actor list
  approved that head (merge-holds `pathLifters`, or `liftersOf` over base merges), the release the
  refusal and ci-status already name. Removing the label re-runs ci-status at the head. A cost,
  risk or verifier reason, a refusal at another head, an approval of another head, a dismissed
  approval, an untrusted reviewer or a report-only run lifts nothing.

- A trusted person's approval of a hold-path head now also carries to a later head when the diff
  between the two touches no hold path and no file a hold path loads (the owner's decision Q10 of
  2026-10-28, #10759), in `merge-holds.mjs` `approvalCarry` and its twin
  `babysit_merge_policy.approval_carry`. The diff is read with the hold-path rules plus the
  enforcement floor and `CARRY_REFUSES` (workflows, actions, `.github/scripts`, `.github/standards`,
  the pipeline config's directory, `scripts/` and `lib/`). Any edit to such a file, a test-only
  or comment-only edit included, needs a new approval, and so do a compare not read whole and a
  head that is not ahead of the approved one. `test_merge_holds_sync.py` derives every file the
  hold paths load and fails on one outside the floor and `CARRY_REFUSES`. The control is still a
  person's approval.
