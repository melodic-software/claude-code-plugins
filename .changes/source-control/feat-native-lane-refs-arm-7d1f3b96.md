---
bump: minor
---

### Added

- `babysit_verify_evidence.py evidence --lane-link` first reads the pull request's issue link by the pr-merge lane's own rule (`babysit_merge_policy._linked_issue`: one closing issue in this repository, or, with none, the one issue its plain `Refs:` lines name) and adds `ineligible` to its line: null when the lane takes the link, else why not, with refusal `verify:ineligible` and no verdict or config read. A failed read refuses. The verdict read that follows takes the link read's pull request instead of reading it again.
- `babysit_verify_evidence.py lane-room` prints whether the pr-merge lane may merge one more of its own pull requests now (`babysit_merge_policy.lane_room`): the gate's run-level refusals (another authority, a post-merge refusal, the effective rung off, a demotion included) as `refusal`, a failed read, or a post-merge answer the gate would not reuse for its age or a changed demotion record (`shared_refusal`'s checks), as `unreadable`, and otherwise the merges in flight against `merge.max-in-flight`. `InFlight` now carries that count.
- `babysit_verify_evidence.py evidence --lane-reviews --base-sha <sha> --rung <rung>` adds `reviews` to a line whose refusal is null: null when the gate would not hold the pull request on its risk score (`lane_risk_refusal`: `babysit_risk.score` and `holding` over the inputs `babysit_merge.score_unattended` builds for a lane pull request, the cost decision included), else why. A failed read, a moved head, or no rung holds. `lane-room` reports the effective rung as `rung`.
