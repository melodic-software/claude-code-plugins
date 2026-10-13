---
bump: patch
---

### Changed

- `/implementation:implement-dispatch` dispatches one fix brief per pull-request head, after every check and review lane on that head has finished, carrying the failing checks, the open review threads and the verifier's failed criteria together, instead of one serial round per source of findings. Workers are also told never to wait with `pgrep -f` on a pattern their own command contains, and to stop their background waits before returning.
