---
bump: patch
---

### Fixed

- `babysit_verify_evidence.py` stops counting a merged or closed pull request's FAILs toward
  another pull request's `verify:repeated-fail` cap. A FAIL of another pull request for the same
  issue counts only while that pull request is open. It also has to be uploaded after the
  issue's newest close of an attempt, meaning the lanes App's capped-close record (parked or not)
  or a pull request for the issue that was closed without merging. So a fresh attempt starts its
  own count, as the owner's 2026-10-29 decision intended. Before this fix, #9241's fresh attempts
  were closed at the cap without any FAIL of their own. The issue's closing-PR query now reads
  `closedAt`, its comments query reads `createdAt`, and the reader drops its unused
  `cap_attempts` field.
