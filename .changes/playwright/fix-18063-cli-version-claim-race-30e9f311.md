---
bump: patch
---

### Fixed

- The once-a-day CLI version check no longer runs twice when two sessions start at the same moment: the shared `cli-version-check.mjs` now reads the clock after it takes its lock ([#18063](https://github.com/melodic-software/claude-code-plugins/issues/18063)).
