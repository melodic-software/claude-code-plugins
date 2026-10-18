---
bump: patch
---

### Changed

- The pr-merge prefilter (`babysit_merge_prefilter.py`) orders the candidates it keeps CLEAN first (`mergeStateStatus`), then oldest `createdAt` first, so a sweep the job timeout cuts short has tried the pull requests likeliest to merge instead of always restarting at the lowest number. `pr-merge.yml` adds both fields to its existing candidate list query, with no per-PR call. A candidate without them sorts last, held candidates are still set aside before any ordering counts, and the gate still checks every candidate as before.
