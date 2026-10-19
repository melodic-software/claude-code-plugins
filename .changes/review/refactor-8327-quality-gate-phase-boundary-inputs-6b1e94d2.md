---
bump: minor
---

### Added

- `/review:quality-gate` takes phase-boundary inputs in every mode: `--worktree <path>`, `--base <sha>`, `--quality-bar` and `--report-only`, so an orchestrator can review a phase diff in a worker's worktree before any pull request exists. With a base SHA the gate runs no pull-request lookup or fetch, and the reviewer gets the diff, the concern tag, the quality bar and its mode's own brief inputs, never the plan rationale or the conversation. The reviewer rates only findings the phase diff causes, including breakage it reaches in untouched files; problems it did not cause go in an unrated `Outside this phase` list that never affects the verdict.
- The `code-reviewer`, `security-reviewer` and `architecture-guardian` agents accept a supplied change set: given a worktree path and base SHA, or the commands to run, they run only those commands, with no pull-request lookup, fetch or remote read, and given a worktree they run every command and read against it, never the invoking checkout. Without one, their change-set step is unchanged.
- `/review:quality-gate` `criteria` and `restatement` modes with `--base` or `--worktree` dispatch a fresh-context `review:brief-reviewer` with the change-set commands instead of reviewing inline: `criteria` with the resolved criteria and the paved-path file, `restatement` once per batch.
