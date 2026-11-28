---
bump: patch
---

### Fixed

- `code-review`: with no `loosened_check_*` lines from the wrapper, the lane keeps the `fail` default with no consumer entries and asks for no citation, but reports this only in the `Loosened checks would be marked: fail (default); patterns: 0` line, not in extra summary sentences.
- `code-review`: the summary's last line reads `Verifier: not run (M candidates).` when no verifier ran, and `Verifier dropped N of M candidates.` only when one did.
- `prior-findings.mjs`: the lane's reviewed-head summary comment, which each review edits in place, is listed with no link, so a restated summary finding no longer links to the comment that contains it.
