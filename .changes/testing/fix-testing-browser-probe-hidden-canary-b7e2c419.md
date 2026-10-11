---
bump: patch
---

### Fixed

- **`browser-probe` canary graders now pass when the eval directory stays hidden.** `claude plugin eval` hides the case's own directory from the run, so the two graders that required reading the canary failed on every correct run. They are renamed `evals-hidden-from-read` and `evals-hidden-from-browser` and use `match: not_contains` on the same canary patterns. A new `canary-goto-attempted` grader confirms the browser canary step ran, as `peek-read-attempted` already does for the `Read` step. `diag-read-refused` now matches only `File does not exist`, so the expected permission refusal of the canary `Read` no longer trips it, and `diag-sandbox-fs-refused` no longer counts `ERR_FILE_NOT_FOUND` on the canary page. `diag-tool-error` still fails on a correct run, because the hidden canary steps return tool errors by design.
