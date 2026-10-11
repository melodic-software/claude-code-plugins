---
bump: patch
---

### Fixed

- video-digest: an auto-caption transcript paragraph no longer repeats the previous paragraph's closing words that a rolling caption carried over: 2 to 12 words compared case- and punctuation-insensitively, dropped only when the opening cue carries them from the cue before it (the cues overlap in time, or the cue starts with the previous cue's words verbatim), so a phrase the speaker genuinely repeats stays ([#6992](https://github.com/melodic-software/claude-code-plugins/issues/6992)).
