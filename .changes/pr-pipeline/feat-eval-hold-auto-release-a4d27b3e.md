---
bump: minor
---

### Added

- pr-merge's scheduled merge job removes `do-not-merge` from a pull request held only for eval evidence (`<!-- pr-hold reason=eval -->`) once a listed human posts `<!-- eval-pair verdict=no-loss validity=VALID head=<sha> -->` for its current head, after a comment naming the record and the head (`release-eval-hold.mjs`). It reuses the merge job's lane token, releases at most five a run, and logs one line per pull request and one per run.
