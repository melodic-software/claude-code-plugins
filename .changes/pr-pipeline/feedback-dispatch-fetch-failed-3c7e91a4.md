---
bump: patch
---

### Fixed

- The dispatchers' FAIL-cap reader (verify-cap.mjs) now runs as an async child process, so it no
  longer blocks the event loop. While it blocked for a minute or more, a reset on the job's idle
  connection to GitHub went unread. The address-feedback dispatch POST then went out on the dead
  socket and failed with `fetch failed` (ECONNRESET), so no round was sent or recorded. A reader
  past its 2-minute limit is still killed and read as not the cap.
- feedback-dispatch.mjs sends the dispatch POST once more when its connection broke before any
  answer (ECONNRESET, UND_ERR_SOCKET), unless a run that POST started is already listed for the
  pull request. An HTTP error answer is never sent again. A failed run's error line now names the
  cause code.
