---
bump: minor
---

### Added

- `merge.lane-arm-gate` (on) lets a pull request held only by `gate` floor paths (the gated workflows, the merge gate's other scripts, the agent settings and instruction files) merge with no person once both review lanes are bound to the main-run review of its head with no finding and no review thread is open (owner decision Q7). `merge.person-held` is the merge-enforcement set that stays with a person whatever the switch says: the pr-merge scripts that apply the holds, `pr-merge.yml`, ci-status, the review workflows, the main-run review's scripts and `pr-verify.yml`. Every `trust` path stays with a person too. `scripts/sync-hold-floor.py` copies both keys into `babysit_risk.py` and `merge-holds.mjs`.
- `merge-holds.mjs` no longer holds a lane-armed path in ci-status or enable-auto-merge; the merge gate decides it. An approval never carries over a push that touches one.
- clear-escalations takes the human-gated label off at the same head when the refusal names lane-armed paths alone and the gate's reader now refuses nothing there.
