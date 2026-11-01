---
bump: patch
---

### Fixed

- A review thread the address-feedback lane answered `UNCERTAIN`, `VALID-defer` or `INCORRECT`
  and left open no longer stalls the pull request with no queue. `feedback-untaken-threads` and
  `feedback-unadjudicated` now add `needs-session` beside their failing status, so a session
  builder takes the thread. While that stop stands on the head, the select job skips the new
  `awaiting-session` reason instead of escalating again; it still clears the stop
  (`stop-resolved`) once no thread is unresolved, and a new head escalates afresh.
