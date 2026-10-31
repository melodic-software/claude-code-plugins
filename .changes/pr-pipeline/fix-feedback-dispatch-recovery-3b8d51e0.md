---
bump: patch
---

### Fixed

- pr-feedback-dispatch's tick now recovers a run whose `dispatch` job failed after it started, as it
  already recovered a cancelled, timed-out or never-started one: runs 41151634518 and 41151650975
  failed on `fetch failed` for #11344 and nothing sent their round again. Each failed or lost run
  sends at most one round per pull request: a finished `pr-unblock` address-feedback run for the
  pull request created after it holds that pull request, read from every run created since. A
  failed run is retried for 2 hours, since a dispatch the API rejects starts no round to end it.
- A pass-only address-feedback round is no longer stranded when pr-verify's FAIL cap cannot be read
  (`verify:unreadable`, as on #11354). It skips only on a cap the reader found; the deadline
  warning is still logged. A FAIL or review round still skips on an unreadable cap.
