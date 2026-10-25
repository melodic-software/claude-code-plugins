---
bump: patch
---

### Fixed

- Intake admission refuses three more kinds of done-when item an unattended lane run cannot perform. A paid eval now also covers `measure-invocation` trigger probes, `/evals:plugin-eval`, and a PR body carrying before-and-after numbers, trigger rates or scores. A validate, dry-run or no-spend form still passes. A live Claude Code CLI run covers `claude -p`, `claude plugin test|install|update|configure`, a headless Claude Code run, and a recorded probe tied to a Claude Code version. A comment instead of a file change covers a comment on this issue as the deliverable, and "No file is changed". The parked concise-skills rollout issues and the CLI-probe issues re-entered the lane through admission after a person removed `needs-human`; they are now refused there (`.github/scripts/intake-triage/admit.mjs`).
