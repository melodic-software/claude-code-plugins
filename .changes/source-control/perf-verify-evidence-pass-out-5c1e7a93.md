---
bump: patch
---

### Changed

- `babysit_verify_evidence.py evidence` takes `--pass-out <file>`: for an allow at the head it
  writes the counted passes with their runs, the first pass's verdict.json and the closing issues
  the judgment read, so ci-status's merge-queue step can hand them to merge-holds.mjs without
  reading them again. The printed report does not change, and a caller that does not pass the flag
  sees no difference.
