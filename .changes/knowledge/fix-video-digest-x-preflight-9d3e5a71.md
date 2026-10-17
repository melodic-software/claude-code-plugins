---
bump: patch
---

### Fixed

- `video-digest` X preflight now rejects a removed or nonexistent status as `unavailable` (no uploader, description or counts), and takes a link post's delegation refusal as `ok` with an empty-media note instead of `transient`. Acquisition fails a removed post permanently (`X post unavailable`) rather than as rate-limited retry-later, and the queue spoke caps degraded retries at 3 per id.
- `video-digest` transcript runs write the slice README after the transcripts, listing only those written; a 0-entry post says no video entries were found.
