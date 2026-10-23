---
bump: patch
---

### Fixed

- pr-merge.yml's `post-merge-dispatch` job caps its dispatch waits at 180 s instead of 300 s. Its whole run took 97-127 s on recent scheduled runs, and the re-run step after the dispatch sleeps up to 170 s while it reads back attempt 2. The lower cap leaves about 6.5 of the job's 15 minutes free, so a timeout no longer lands after the re-run POST and leaves attempt 2 unrecorded.
- Both dispatch steps send the dispatch again after no response only when gh's error shows the connection failed before the request was sent (a `dial tcp` error or a failed TLS handshake). A reset or timeout on an open connection may follow GitHub creating the run, so the step now warns and stops, as it does on exhaustion.
