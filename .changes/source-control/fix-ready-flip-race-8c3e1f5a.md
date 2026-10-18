---
bump: patch
---

### Fixed

- `pull-request ready`: after the last push the flip waits up to 120 seconds for the head commit's `pull_request` workflow runs to register, so a push seconds before the flip no longer leaves its runs skipping every lane on a stale draft payload. After the flip it checks the head's runs for a skipped run, or none, within 180 seconds; it re-fires the ready event once (undo, then ready) and reports a second skip rather than looping.
