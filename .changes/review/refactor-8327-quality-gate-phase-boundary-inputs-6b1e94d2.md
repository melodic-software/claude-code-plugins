---
bump: minor
---

### Added

- `/review:quality-gate` takes phase-boundary inputs in every mode: `--worktree <path>`, `--base <sha>`, `--quality-bar` and `--report-only`, so an orchestrator can review a phase diff in a worker's worktree before any pull request exists. With a base SHA the gate runs no pull-request lookup or fetch, and the reviewer gets the diff, the concern tag, the quality bar and its mode's own brief inputs, never the plan rationale or the conversation.
- The `code-reviewer`, `security-reviewer` and `architecture-guardian` agents accept a supplied change set: given a worktree path and base SHA, or the commands to run, they run only those commands, with no pull-request lookup, fetch or remote read. Without one, their change-set step is unchanged.
- `/review:quality-gate` `criteria` mode with `--base` or `--worktree` dispatches a fresh-context `review:brief-reviewer` with the change-set commands, the resolved criteria and the paved-path file instead of reviewing inline.
