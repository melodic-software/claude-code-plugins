---
bump: patch
---

### Fixed

- video-digest picks YouTube's original `en-orig` captions over the machine-translated `en` track when a video has no manual English captions, and fetches `en-orig` alone when the `en` download fails (often HTTP 429) ([#6740](https://github.com/melodic-software/claude-code-plugins/issues/6740)).
