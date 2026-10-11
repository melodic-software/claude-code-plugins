---
bump: patch
---

### Fixed

- video-digest `resume` reports a closed slice as having nothing to resume and leaves its continuation prompt untouched, writes only slice-relative paths into `continuation-prompt.md`, stops before vision with a re-run instruction when the temp session dirs are gone, and rejects a slug that is not a single slice-name segment ([#6822](https://github.com/melodic-software/claude-code-plugins/issues/6822)).
