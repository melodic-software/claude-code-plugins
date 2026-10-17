---
bump: patch
---

### Changed

- Unattended GitHub loops follow one API budget, in the GitHub provider reference: the pull-request monitor watch and babysit Monitor fallback poll at 60 s and stop on a rate-limit error; merge-state, merge-queue and queue-entry waits poll REST at 60 s and read `isInMergeQueue` once; the babysit merge gate polls an async merge at 60 s and reads queue state once after a CLI merge.
