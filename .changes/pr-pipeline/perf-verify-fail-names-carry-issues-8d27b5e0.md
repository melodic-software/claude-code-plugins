---
bump: patch
---

### Changed

- The pr-verify resolver, the verifier-notes poster (`verify-notes.mjs`) and `pr-feedback-dispatch.yml`'s FAIL filter accept a verdict artifact name that ends with `-i` and the dot-joined numbers of the issues the verdict records, so `write-verdict.mjs` can start writing them later. The notes poster refuses a name whose issues are not the ones its verdict JSON records. `test_verify_rules_sync.py` checks that the gate and these readers accept the same names.
