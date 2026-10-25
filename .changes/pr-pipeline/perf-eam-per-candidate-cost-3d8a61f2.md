---
bump: patch
---

### Changed

- enable-auto-merge logs each verifier read's cost, `enable-auto-merge: #<n> calls=<total> github-token=<n> paginated=<n> ms=<elapsed>`, read from the reader's `babysit-gh-calls` stderr line, and adds the same rows to the step summary even on a run that raised nothing. `calls` counts gh invocations; a paginated one (the artifact listing) made one request per page. A reader that exits non-zero is now reported by its last error line, not by the calls line (`.github/scripts/pr-merge/enable-auto-merge.mjs`).
- pr-merge's merge job records each gate candidate's gh invocations as `calls` in its summary row (`.github/workflows/pr-merge.yml`).
