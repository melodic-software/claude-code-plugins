---
bump: minor
---

### Added

- `merge.lane-arm-gate` (on) and `merge.person-held` (owner decisions Q7 and Q5): a pull request held only by the merge gate's own code, `babysit_risk.py` and the `.github/scripts/pr-merge/` scripts, merges with no person once both review lanes are bound to the main-run review of its head with no finding, no review thread is open, and pr-merge has attested it. Every other `trust` and `gate` row stays with a person, and `scripts/sync-hold-floor.py` refuses a `gate` row outside the merge gate's code that `merge.person-held` does not list.
- pr-merge's `lane-armed` job (`lane-armed.mjs`) posts the check run `pr-merge/lane-armed` at a head whose gate passed its lane-armed paths and whose hold floor does not shrink against the base, then re-runs its red ci-status job. Each attestation is one `lane-armed {...}` record line, in the check run and as a notice; each refusal logs the failed condition.
- ci-status (`merge-holds.mjs` `laneArmedHold`) holds a lane-armed path until that check run is at the head and names a run of `pr-merge.yml` on the default branch, started by schedule or workflow_dispatch, whose commit is on that branch and which uploaded the run-scoped attestation artifact; a trusted person's approval still lifts it.
- `pr-review-main.yml` also reviews a pull request after a red ci-status when it changes main's lane-armed code, so neither the red status nor the human-gated label blocks the review the attestation needs. clear-escalations lifts that label at the same head once the gate's reader refuses nothing there.
- The review criteria `pr-review-main.yml` copies from main (`plugins/review/skills/**`, `plugins/review/reference/**`) are `enforcement` floor rows: a change to them waits for a clean bound security review.
