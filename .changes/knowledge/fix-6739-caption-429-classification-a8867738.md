---
bump: patch
---

### Fixed

- video-digest reports a caption download that is still rate-limited (HTTP 429) after its retries as a rate limit with a wait-and-retry fix path, instead of "No English captions found" ([#6739](https://github.com/melodic-software/claude-code-plugins/issues/6739)).
