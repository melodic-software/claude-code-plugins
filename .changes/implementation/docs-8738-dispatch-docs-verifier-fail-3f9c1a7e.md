---
bump: minor
---

### Changed

- `/implementation:implement-dispatch` now matches `phase-verifier`: an unsanctioned edit to an existing test or check file is a FAIL, not a finding, and brief item 13 quotes the verifier's definitions of a test or check file and of a sanctioned edit. Step 3 checks every return against item 13, mechanical phases included, and the verifier applies the same rule at the phase boundary, handed the brief's item 13 sanctions.
- The orchestrator creates the throwaway worktree whenever the phase diff touches a test or check file, not only when holdout tests are on, and fills it with the full phase state, uncommitted and untracked changes included, so the verifier's base-restored re-run checks the actual implementation.

### Fixed

- Step 3 described the `testing` plugin's `test_guards_enabled` hook as asking for a reason. It adds an advisory note, and denies an added skip or removed test block only under `rules: {test-weaken-block: error}`; it never asks.
