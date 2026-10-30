---
bump: patch
---

### Changed

- The merge gate's hold floor now covers the code pr-unblock's adjudicator reads a linked issue's spec text through (`resolve-pr.mjs`, `write-verdict.mjs`, `admit.mjs`, `select-trusted-text.mjs`, `lib/publish-gate.mjs`, `.github/recurring-schedule.json`, `charge-words.json`), as enforcement paths a clean security review clears.
