---
bump: patch
---

### Fixed

- The surface table and the MS-13 row now say an `omitClaudeMd` agent whose definition comes from
  managed settings loads no instruction file, as the MS-13 quote already does, and MS-13's recheck
  trigger covers what such an agent keeps. `migrate`'s verification probe gives its reason for
  `--model sonnet` and points at the model aliases section
  ([#6916](https://github.com/melodic-software/claude-code-plugins/issues/6916)).
