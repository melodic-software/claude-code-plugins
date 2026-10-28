---
bump: patch
---

### Fixed

- pr-unblock's `publish-feedback` re-reads each thread against the reviewed heads `address-feedback-select` kept it on, which `run.json` now records as `reviewed_heads`, not against the reviewed-head markers as they are at publish. A review lane edits its one marker in place, so once it reviewed the round's fix push the marker named only the fix head, the re-read dropped the thread as changed, its reply never posted, and the next round escalated `feedback-untaken-threads`. The comment-id, resolved, comment-count and moved-head checks are unchanged; a `run.json` without `reviewed_heads` reads the markers as before.
