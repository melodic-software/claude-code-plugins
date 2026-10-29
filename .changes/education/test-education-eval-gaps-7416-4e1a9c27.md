---
bump: patch
---

### Added

- Six outcome eval cases for behavior no case covered: `te-root-declared-substitution` (a declared workspace root holding `$(…)` is refused and never run), `te-root-ask-once`, `te-root-adopt-existing` and `te-root-headless-skip` (the rung 3 root question), `te-slug-collision-guard` (the project slug and the slug collision hash), and `ex-invalid-rung-layer` (an invalid `explain_starting_rung` repository value is named and dropped). Each grader has must-pass and must-fail samples. ([#7416](https://github.com/melodic-software/claude-code-plugins/issues/7416))

### Changed

- The `te-primer-no-workspace` eval case grants `Write` and adds a `no-workspace-write` grader, so a primer that writes `MISSION.md`, `GLOSSARY.md` or a `learning-records/` file now fails the case.
