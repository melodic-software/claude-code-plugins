---
bump: minor
---

### Added

- New config: `merge.gate-budget-minutes` (a whole number of minutes; absent is no budget). The
  pr-merge workflow's gate loop starts no further candidate once it has run that long, and the
  candidate in progress finishes first, so the budget never stops a gate between its check and its
  merge-queue write. Each run starts after the last candidate the previous loop reached, read from
  the `pr-merge-gate-cursor` artifact of a scheduled or hand-started `pr-merge.yml` run on the
  default branch, and wraps
  round to the lowest PR number, so every candidate is reached across runs. This repository sets
  10, and the merge job's timeout returns from 55 to 30 minutes as a ceiling above it. `version`
  stays 2.
