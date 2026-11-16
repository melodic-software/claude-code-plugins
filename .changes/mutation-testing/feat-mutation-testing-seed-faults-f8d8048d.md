---
bump: minor
---

### Added

- **`/mutation-testing:seed-faults`.** Plants a small number of hand-written, realistic defects
  (5 by default, `--count` to change it) one at a time in a throwaway worktree outside the
  repository, runs the selected tests against each, and reports seeds caught over seeds planted
  with each surviving seed's `file:line` and change. The result is reported as an estimate of the
  suite's thoroughness, never a defect count. Nothing planted is committed, the seed ledger stays
  outside the worktree, the worktree is removed on every exit path, and the user's checkout is
  checked against a snapshot before any result is reported. `--reviewer` grades a fresh-context
  reviewer that is never told seeds were planted. The test command is resolved and never guessed,
  as in `audit`.

### Changed

- `/mutation-testing:principles` answers when to use hand-seeded faults rather than generated
  mutants and names `seed-faults` in `## Next`.
