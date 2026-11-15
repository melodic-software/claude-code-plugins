---
bump: patch
---

### Changed

- `narrate.py` retries a failed edge-tts paragraph after 5, 20 and 60 seconds instead of 1, 2 and 4, so a
  Microsoft endpoint that drops requests for a few seconds recovers before the whole script falls back to the
  next backend. Other backends keep 1, 2 and 4 seconds.
