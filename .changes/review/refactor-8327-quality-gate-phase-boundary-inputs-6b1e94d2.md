---
bump: minor
---

### Added

- `/review:quality-gate` takes phase-boundary inputs in every mode: `--worktree <path>`, `--base <sha>`, `--quality-bar` and `--report-only`, so an orchestrator can review a phase diff in a worker's worktree before any pull request exists. With a base SHA the gate runs no pull-request lookup or fetch, and the reviewer gets only the diff, the concern tag and the quality bar.
