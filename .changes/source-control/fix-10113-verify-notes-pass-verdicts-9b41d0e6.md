---
bump: none
---

Test only: `test_verify_rules_sync.py` follows verify-notes.mjs, which now reads names through `write-verdict.mjs` `isVerdictName` and `readVerdict` (pass names included) in place of `isFailName`, and pr-feedback-dispatch.yml's listing, which now keeps pass names too. No shipped behavior of the plugin changes.
