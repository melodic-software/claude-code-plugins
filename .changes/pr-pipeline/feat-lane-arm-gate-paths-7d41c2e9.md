---
bump: minor
---

### Added

- `merge.lane-arm-gate` (on) and `merge.person-held` (owner decision Q7): a pull request held only by lane-armed `gate` floor paths merges with no person once both review lanes are bound to the main-run review of its head with no finding and no review thread is open. No path is lane-armed yet: `merge.person-held` holds every `gate` row, as an independent security review of #10966 required, and `scripts/sync-hold-floor.py` refuses to leave one out while the switch is on. The list covers the pr-merge scripts with what they import or run, the rate guard, `.github/actions/report-check-run/**`, the main-run review's scripts, and the review criteria and agent settings and instruction files. Every gated workflow is added automatically, so a workflow that gains a credential is person-held at once. `trust` paths stay with a person as well. The script copies both keys into `babysit_risk.py` and `merge-holds.mjs`.
- `plugins/review/skills/**` and `plugins/review/reference/**`, which the main-run review copies from main as its criteria, are `gate` floor paths and person-held, outside the trusted-author lift.
- clear-escalations removes the human-gated label at the same head when the refusal names lane-armed paths alone and the gate's reader now refuses nothing there. An approval never carries over a push that touches a lane-armed path.
