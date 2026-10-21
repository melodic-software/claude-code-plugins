---
bump: patch
---

### Fixed

- The unattended merge gate reads the merge config at the default branch head as well as at the pull request's base SHA, which GitHub never moves as the default branch advances, and takes the stricter value of each setting: the lower `merge.rung` and `babysit_loop_merge`; `report-only`, `require-verifier-verdict`, `high-path-floor` and `c2-contradictions` when either side sets them; both sides' `denied-paths`, `floor-paths`, `floor-script-scopes` and `check-inputs` (each side's `check-inputs` in a git diff of its own); the smaller `max-changed-lines`, `max-changed-files` and `max-queue-ejections`; the stricter `dependabot.mode` and `dependabot.majors`. `merge.risk-escalation-minutes` keeps the base's value, and `merge.max-in-flight` is read at the head alone. So a tightening on the default branch reaches pull requests opened before it.
- Which reads refuse and which fall back: an unreadable head config, or two different agent identities, refuses. A different authority, or an identity set on one side only, is the stop `authority-differs`, which dequeues the identity's entries as `rung: off` does. A failed re-read of `merge.max-in-flight` falls back to the lower of the base's and the head's cap. A failed listing of the head's `check-inputs` keeps the base's result. The enqueue reads the head again when the gate took its config from the run cache, and holds if the config changed.
- The plain `--merge` refuses a token acting as the agent identity at either the base or the default branch head, so an identity rotation never blocks a human merge.
