---
bump: patch
---

### Fixed

- video-digest `watch` no longer exits 1 after downloading a YouTube video that has no captions in any language: in full mode with the video downloaded, an exhausted caption ladder returns the entry with `caption: null`, and the transcript strategy selects `asr` when it is detected or completes with a recorded `transcriptDegradation`. `transcript` mode, which downloads no media, still stops on an exhausted ladder.
