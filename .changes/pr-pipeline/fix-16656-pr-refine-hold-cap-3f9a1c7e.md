---
bump: patch
---

### Fixed

- The monitoring lane reads up to 12 unread pr-refine runs per pass, up from the default of 6. Signal 13 now reads all but pr-refine's busiest hour in one pass, so its incident can clear ([#16656](https://github.com/melodic-software/claude-code-plugins/issues/16656)).
