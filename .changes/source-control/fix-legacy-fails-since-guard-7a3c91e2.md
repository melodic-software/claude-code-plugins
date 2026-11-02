---
bump: patch
---

### Fixed

- `babysit_verify_evidence.py legacy-fails` refuses, writing nothing, when the whole artifact listing holds a FAIL uploaded before `--since`, naming the earliest such artifact, its run and its upload time so the operator can lower `--since`. A FAIL of a run created before `--since` but uploaded at or after it is still added through the listing. A checkpoint whose listing kept no upload times lists again.
