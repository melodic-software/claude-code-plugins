---
bump: patch
---

### Fixed

- **`/review:explain-change` removes its temp directory.** The directory that holds the pull
  request's `facts.json` and `pr.diff` is now removed when the run ends, at whatever step it
  stops, after the reader is done with a connected view. The page never lives there, so nothing
  the reader opens is lost. Each run used to leave one `tmp.*` directory in the OS temp folder
  ([#9571](https://github.com/melodic-software/claude-code-plugins/issues/9571)).
