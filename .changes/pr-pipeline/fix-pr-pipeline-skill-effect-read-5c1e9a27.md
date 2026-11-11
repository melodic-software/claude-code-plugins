---
bump: minor
---

### Changed

- A skill activity's `effect` must be `read`. The schema and resolve-config (rejection 17, `skill-not-read`) refuse any other effect at config load, in any lane, so every skill runs in `pr-run-activity-read.yml` and hands its change to a script activity.
- `pr-run-activity-write.yml` runs scripts only and fails red with `skill-in-write-runner` before the mint for any skill, not just an issue skill.

### Removed

- The write runner's skill path, which no config can now reach: the claude-code-action step, its lane commit branch and promote step, the turn-cap, model-turn and gate-verdict checks, the skill reply upload, the lane-outcome record, and the unused `claude-code-oauth-token` secret. The write runner's report no longer carries a `lane-outcome`.
- The schema's head-test-check limits on a skill whose effect is not `read`, which no skill can now have.
