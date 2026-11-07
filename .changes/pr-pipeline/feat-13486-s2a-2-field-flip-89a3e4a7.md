---
bump: minor
---

### Changed

- An issue's Work status is read from and written to the Work status field; status labels no longer decide it, though a hold label still holds on top of it. `write-status.mjs` drops the label mirror (`statusMirror`, `labelsAfter`, `writeStatus`), and `check-born-triaged` fails when resolve-config's dependencies do not install.
