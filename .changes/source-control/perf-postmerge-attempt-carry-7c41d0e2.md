---
bump: patch
---

### Changed

- `/source-control:babysit-prs`: the post-merge check (`babysit_postmerge.py`) answers an earlier attempt of a re-run full run from the file named in `BABYSIT_POSTMERGE_ATTEMPTS` before reading it, when the file holds that run's attempt, completed, at the same head SHA. A completed attempt never changes, so the answer decides as the read would. The check writes back the completed attempts it used; a check that looks up no attempt leaves the file as it was. A missing or malformed file (another version or repository, a key that does not match its entry, an attempt not completed, a field the reader does not use) is no file, and every attempt is read as before. Without the variable nothing changes.
