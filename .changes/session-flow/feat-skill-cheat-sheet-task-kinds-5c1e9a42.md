---
bump: minor
---

### Added

- `workflow`'s stage definitions end with a Task kinds table: the stages a small fix, a bug, a feature, a refactor, a UI change and a release enter, in order, and the stages each skips, naming no skills. Default mode reads the kind's row for the stage list and its skips, and points at the marketplace's skill cheat sheet to look the sequence up with the skills that run each stage.
- An eval case checks that "fix bug X" gets the Bug row's stages.

### Changed

- The quick-change and bug on-ramps point at their Task kinds rows instead of stating their entry stage.
