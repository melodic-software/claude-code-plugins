---
bump: patch
---

### Fixed

- video-digest's `init-watch-checklist.js --force` keeps every ticked row (matched by row id) and the Resume notes when it regenerates the floors and per-sheet rows, instead of resetting the checklist to the template ([#6815](https://github.com/melodic-software/claude-code-plugins/issues/6815)).
