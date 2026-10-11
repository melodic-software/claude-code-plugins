---
bump: patch
---

### Fixed

- video-digest keeps an English caption file already written when another caption track's download fails (for example a translated track rate-limited with HTTP 429), records the failed track in `transcriptDegradation`, no longer requests YouTube's translations of manual tracks unless no English track landed, and prefers the original `en-orig` track over the bare auto `en` track ([#6812](https://github.com/melodic-software/claude-code-plugins/issues/6812), [#6740](https://github.com/melodic-software/claude-code-plugins/issues/6740)).
