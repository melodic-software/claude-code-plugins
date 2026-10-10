---
bump: patch
---

### Fixed

- video-digest: when a YouTube video has no manual English subtitles, the caption ladder now picks the original `.en-orig.vtt` speech recognition over the bare `.en.vtt`, which can be YouTube's machine translation and produced garbled transcripts.
