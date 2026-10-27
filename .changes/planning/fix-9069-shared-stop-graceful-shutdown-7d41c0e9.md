---
bump: patch
---

### Fixed

- Shared interview: `share.sh stop` and `restart` now ask the server to shut down through its control listener before ending it, so the server writes the usage summaries it holds on every OS. On Windows the stop used to end the process at once, losing every held summary; a one-on-one session there recorded no usage counts at all. A server that refuses or does not exit within 15 seconds is still force-ended.
