---
bump: minor
---

### Changed

- `phase-verifier` now fails a criterion when the diff edits, deletes or skips a test or check file (test files, runner configs, lint and hook configs, check scripts, CI workflows, eval cases and graders) that the dispatch did not name. It lists the changed paths itself, and when it is handed a throwaway worktree it re-runs the check there with those paths restored from the base.
