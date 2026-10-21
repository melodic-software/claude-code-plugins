---
bump: minor
---

### Changed

- `/implementation:implement-dispatch` now matches `phase-verifier`: an unsanctioned edit to an existing test or check file is a verifier FAIL, not a finding, and brief item 13 quotes the verifier's definitions of a test or check file and of a sanctioned edit. Step 3 no longer lists test paths itself; the verifier is the one gate.
- The orchestrator creates the throwaway worktree whenever the phase diff touches a test or check file, not only when holdout tests are on, so the verifier's base-restored re-run always has somewhere to run.

### Fixed

- Step 3 described the `testing` plugin's `test_guards_enabled` hook as asking for a reason. It adds an advisory note, and denies an added skip or removed test block only under `rules: {test-weaken-block: error}`; it never asks.
