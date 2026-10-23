---
bump: patch
---

### Changed

- The verifier-notes poster (`verify-notes.mjs`) and `pr-feedback-dispatch.yml`'s FAIL filter accept a FAIL artifact name that ends with `-i` and the issues the verdict records, ascending, each once, joined by dots, so `write-verdict.mjs` can start writing them later. `pr-feedback-dispatch.yml` fails its run on a FAIL-shaped name no reader takes rather than skipping it, and anchors its filter at the true end of the name; the notes poster refuses a name whose issues are not the ones its verdict JSON records. The resolver's name pattern (`resolve-pr.mjs` `NAME`, checked by `isVerdictName`) follows the same grammar, though its already-judged lookup still builds exact names and finds an issue-named FAIL only once the writer change teaches it to. `test_verify_rules_sync.py` checks that the gate, the resolver's pattern (`isVerdictName`; it does not exercise `judged()`), the notes poster and the workflow filter accept the same names, with the same 10-digit pull request bound and 194-character limit.
