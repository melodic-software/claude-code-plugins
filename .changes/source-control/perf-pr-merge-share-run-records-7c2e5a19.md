---
bump: patch
---

### Changed

- `babysit-prs` merge gate: in the pr-merge lane, the verdict reader shares a FAIL's run record for two minutes and an untied FAIL's recorded head ref for the run across the run's gate processes, instead of reading them again for every candidate. A stale FAIL record still refuses, because a FAIL counts whether its run is running or finished and a re-run keeps every field that decides whether the run is pr-verify's; a PASS's run record is still read by each gate process, so a re-run that undoes a completed success never allows. The default branch and the base's rules are also shared for two minutes, a failed read never; before an enqueue, any the gate took from the run cache are read again, and a change holds.
