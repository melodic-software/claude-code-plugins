---
bump: patch
---

### Fixed

- video-digest: a watch that fails before its slice records the temp session (an acquisition error, a 429, an unsupported URL) now removes the three temp directories it made, including the downloaded video, instead of leaving them in the OS temp dir. Once `watch.json` records them they stay for `--recover`.
