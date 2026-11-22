---
bump: patch
---

### Fixed

- A pr-verify FAIL on a new head now posts its fail-note when an earlier head's note is still open on the same file. verify-notes decided a note was already posted from `commit_id`, which GitHub moves to the newest head on a note that is not outdated; it now reads `original_commit_id`, which stays at the head the note was posted on.
