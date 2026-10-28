---
bump: patch
---

### Changed

- The lanes adopt a trusted person's pull request after 2 hours of no trusted-actor push, comment or label change (`adoption.idle-hours`), down from 24. A session waiting in the GITHUB_TOKEN gate is idle for up to 2 hours during a breaker trip, so a longer quiet period no longer shows the session is still working. Pull requests here open ready, so being non-draft does not show one is finished.
