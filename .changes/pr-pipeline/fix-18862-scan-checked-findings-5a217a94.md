---
bump: patch
---

### Fixed

- The `maintenance-scan-architecture` Scan job no longer fails with `EACCES` on every run that returns findings: its check wrote the kept items back over the file `open-lane-output` opens read-only (mode 0444). The check now writes them to `CHECKED_FILE`, a separate path, and the credential scan, hash and upload read that copy.
