---
bump: patch
---

### Fixed

- video-digest watch: a run whose transcript came from the optional ASR rung now feeds the ASR cues to frame densification, instead of an empty cue list that recorded `densificationWindows: 0`. `writeEnvelopeTranscriptArtifacts` returns the cues each transcript was built from (caption or ASR) per entry, and `run-watch.js` passes the primary entry's cues to watching. A captioned run passes the same cues as before.
