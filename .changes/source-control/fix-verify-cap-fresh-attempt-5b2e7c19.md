---
bump: patch
---

### Fixed

- `babysit_verify_evidence.py` stops counting a merged or closed pull request's FAILs toward
  another pull request's `verify:repeated-fail` cap. A FAIL of another pull request for the same
  issue counts only while that pull request is open. It also has to be uploaded after the
  issue's newest close of an attempt: either the lanes App's capped-close record (parked or not)
  or the unmerged close of a lanes App pull request for the issue. A pull request found only by a
  FAIL's name gets one state read per reader, and only when one of its FAILs could count. Each
  fresh attempt now starts its own count, as the owner's 2026-10-29 decision intended. Before
  this fix, #9241's fresh attempts were closed at the cap without any FAIL of their own. The
  issue's closing-PR query now reads `closedAt` and author, its comments query reads
  `createdAt`, and the reader drops its unused `cap_attempts` field.
