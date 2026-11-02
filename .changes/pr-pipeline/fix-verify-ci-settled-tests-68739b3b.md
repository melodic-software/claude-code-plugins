---
bump: patch
---

### Fixed

- pr-verify no longer fails a head on a test-run claim the head's CI already settled. Each job in
  `upstream-jobs.json` now carries its job page URL, and the prompt says a suite's job that
  concluded `success` on the judged head meets a done-when "X exits 0" item and settles any "not
  run" or "likely fails" doubt about that suite; the diff is still judged for a test that cannot
  fail or was weakened. The judging jobs' permissions and tool rules do not change.
