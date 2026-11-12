---
bump: patch
---

### Changed

- The pr-merge wake description names its one-read pre-check: the wake ends with nothing armed when main's newest full dispatch run's head commit lacks the newest lanes App commit on main (`babysit_postmerge.py --uncovered-at`), and any other answer runs the usual path.
