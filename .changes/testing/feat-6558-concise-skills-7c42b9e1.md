---
bump: patch
---

### Added

- Outcome eval cases for `audit`, `check`, `cleanup`, `diagnose`, `plan`, `run-e2e`, `test-value` and `write`, and frozen trigger-probe sets for every model-invoked skill.

### Changed

- Model-invoked skill bodies and their spoke files rewritten to the skill criteria in fewer words, with descriptions unchanged; `write` states more plainly that refactoring waits for a green run and that each `Refactor checkpoint:` line is repeated in the summary, and `check-visual-parity` that a kept mismatch needs a `pixel_tolerance` entry in `docs/conventions/testing.yaml`.
