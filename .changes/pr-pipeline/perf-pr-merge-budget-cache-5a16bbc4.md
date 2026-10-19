---
bump: patch
---

### Changed

- The pr-merge workflow's merge job logs its API budget through the shared `log-api-budget` action,
  for the lane token and the job's own token, at mint and at job end, so the reading also lands on a
  run that times out. A `sweep-cost=` line (both tokens' spend since mint, candidates listed,
  candidates reached) goes to the log and the step summary. The action gains a `costs` output.
- The merge job keeps the verdict reads that never change (FAIL run records of pr-verify origin,
  FAIL head refs by artifact id, run heads found on main) across runs with `actions/cache`, under a
  new key per run, restored by prefix. Each kept read can only count a FAIL; everything else is
  dropped (`.github/scripts/pr-merge/carry-run-cache.mjs`).
