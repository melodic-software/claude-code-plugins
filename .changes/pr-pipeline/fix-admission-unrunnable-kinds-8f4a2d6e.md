---
bump: patch
---

### Fixed

- Intake admission refuses three more kinds of done-when item an unattended lane run cannot perform. A paid eval now also covers `measure-invocation` trigger probes, `/evals:plugin-eval`, and a PR body carrying before-and-after numbers, trigger rates or scores. A validate, dry-run or no-spend form, and `measure-invocation`'s model-free `score`, `compare` and `emit-plugin-eval`, still pass. A live Claude Code CLI run covers `claude -p`, `claude plugin test|install|update|configure` when the item runs it or names its exit or result (not when it only shows the command), a headless Claude Code run, and a recorded probe tied to a Claude Code version. A comment instead of a file change covers an item that opens with, or records its result in, a comment on this issue, and an item that is only "No file is changed". The parked concise-skills rollout issues and the CLI-probe issues re-entered the lane through admission after a person removed `needs-human`; they are now refused there (`.github/scripts/intake-triage/admit.mjs`).
