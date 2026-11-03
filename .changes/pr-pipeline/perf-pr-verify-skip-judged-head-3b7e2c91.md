---
bump: patch
---

### Changed

- pr-verify reads the key's credit history only for a head it would judge: the `check-intent-credit` job is gone, and its gate, carried record and skipped-leg report run inside `check-intent` after the resolver, the trigger gate and the reads hand-on. A run that skips at the resolver (a judged head, a draft, a run red for anything but a hold, no single PR) no longer spends the gate's run-list and job-list reads (4 GITHUB_TOKEN calls) or its own VM. A key the gate skips runs no pre-judge setup and no judge, writes no "no verdict" failure, and hands on through the `skip-key` job output, so `check-intent-subscription` now takes the carried reads instead of reading the PR again.
