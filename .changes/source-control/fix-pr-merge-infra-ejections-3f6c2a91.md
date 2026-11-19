---
bump: patch
---

### Fixed

- stop counting infra merge-queue removals toward merge.max-queue-ejections

  The babysit-prs gate and enable-auto-merge no longer count a removal whose
  merge-group run failed on infra alone: a GitHub rate limit, the API read
  or stop floor, a verify:unreadable refusal, the lanes kill switch, a lost
  runner, or a job main failed at the same time. Every failed job must name
  such a cause, so a real check failure beside one still counts. The new
  merge.queue-ejection-infra-causes list names which causes apply (default
  all); every cause excuses a removal only after its reset
  or an hour. Each excused removal gets a queue-ejection notice, and older
  removals are found past the newest page of failed merge-group runs.
