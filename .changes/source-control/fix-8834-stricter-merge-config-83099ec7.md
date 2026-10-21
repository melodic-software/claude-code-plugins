---
bump: patch
---

### Fixed

- The unattended merge gate (both lanes) and the plain `--merge` identity refusal now read the merge config at the default branch head as well as at the pull request's base SHA, which GitHub never moves as the default branch advances, and take the stricter value of each setting: the lower `merge.rung` and `babysit_loop_merge`, either side's `report-only`, `require-verifier-verdict`, `high-path-floor` and `c2-contradictions`, the union of `denied-paths`, `floor-paths`, `floor-script-scopes` and `check-inputs`, the smaller `max-changed-lines`, `max-changed-files` and `max-queue-ejections`, the stricter `dependabot.mode` and `dependabot.majors`. A different authority on the default branch disables the lane, and a different `agent-identity` or an unreadable head config refuses. So a tightening on the default branch reaches pull requests opened before it. `merge.max-in-flight` is still read at the head alone; a failed head read now refuses instead of falling back to the base's cap.
- A `merge.authority` on the default branch that differs from the base's is the stop `authority-differs`, so the identity's queued entries leave as under `rung: off`. A failed re-read of `merge.max-in-flight` falls back to the lower of the base's and the head's cap. A magic pathspec (such as `:!x`) in the head's `merge.check-inputs` is ignored, so it cannot remove a base path. A malformed cached head config is read again instead of crashing the run.
