---
bump: patch
---

### Fixed

- The dispatchers' FAIL-cap reads take the run records, run heads and head refs pr-merge carried,
  fetched with its listing on the job's first read. Without them each read asked GitHub about
  every FAIL in the repository (458 on 2026-10-31, 1,252 reads), was killed at its 120 s
  limit with no answer after spending 119 to 188 calls, and let the fix round run. Those reads
  were 94% of a heavy `pr-unblock-dispatch` run's calls. Reads now finish, so a pull request past
  the FAIL cap gets no round from these reads.
