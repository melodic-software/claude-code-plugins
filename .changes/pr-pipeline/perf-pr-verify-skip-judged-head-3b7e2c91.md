---
bump: patch
---

### Changed

- pr-verify reads the key's credit history only for a head it would judge: the `check-intent-credit` job is gone, and its gate and skipped-leg report run inside `check-intent` after the resolver, the trigger gate and the reads hand-on. A run that skips at the resolver (a judged head, a draft, a run red for anything but a hold, no single PR) no longer spends the gate's reads or its own VM. A key the gate skips runs no pre-judge setup and no judge, writes no "no verdict" failure, and hands on through the `skip-key` job output, so `check-intent-subscription` now takes the carried reads instead of reading the PR again.
- The gate now reads the key's credit stop from one artifact marker (ci-workflows check-key-credit at `bc62beb`): one artifact-list call per judged run instead of a run list and up to three job lists. After a judge step's credit-stop handoff, `check-intent` writes, scans and uploads the artifact the gate's `marker` output names, kept one day; the step that carried a record forward is gone, since the window counts from the marker's upload. pr-verify's other ci-workflows actions move to the same pin.
