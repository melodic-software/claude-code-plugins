---
bump: patch
---

### Fixed

- The pr-merge lane's verdict gate (`babysit_verify_evidence.py`) no longer counts a pr-verify FAIL whose verifier run judged a `pr-require-checks` run that started while the pull request was a draft. Such a run skips every suite, so its FAIL ("no tests ran") said nothing about the change. Before, it refused the head as `verify:fail`, later heads as `verify:earlier-fail`, and counted toward `merge.max-verify-fails` for this and other pull requests for the same issue. The FAIL is dropped only when every checks run at its head created before the verifier run ran ci-status's `Note a draft` step. Any failed or short read keeps it. This is the same rule resolve-pr.mjs uses.
