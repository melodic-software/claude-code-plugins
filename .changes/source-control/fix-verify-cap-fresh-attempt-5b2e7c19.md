---
bump: patch
---

### Fixed

- `babysit_verify_evidence.py` stops counting a merged or closed pull request's FAILs toward
  another pull request's `verify:repeated-fail` cap. A FAIL of another pull request for the same
  issue counts only while that pull request is open. It also has to be uploaded after the
  newest of the lanes App's capped-close records (parked or not) on at least one issue it is for,
  so a record on one issue erases no other issue's FAILs. An unreadable FAIL run of an open pull
  request refuses only when it does not predate the record on every issue that pull request is
  for. A pull request found only by a FAIL's name gets one state read per reader, and only when
  one of its FAILs could count. Each fresh attempt now starts its own count, as the owner's
  2026-10-29 decision intended. Before this fix, #9241's fresh attempts were closed at the cap
  without any FAIL of their own. The issue's comments query now reads `createdAt`, and the reader
  drops its unused `cap_attempts` field.
