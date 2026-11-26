---
bump: patch
---

### Fixed

- A pull request whose compare lists 300 files or more is no longer refused on the count. `merge-holds.mjs` `sameNetChange` (the cost-decision and approval carries in the merge gate and ci-status's cost-hold step) reads the two compares' `application/vnd.github.diff` texts when either listing caps or gives a file no patch, and compares every file's patch and mode from them (`diffFiles`, `needsDiff`). The new `wholeCompare` pages a compare's commits 100 at a time to `total_commits`, past the 250 an unpaged read lists, and takes the files from the diff past 300; `apply-dependency-verdict.mjs` (the fix path, and the merge path past the pull request commit list's 250), `publish-feedback.mjs` `fixesLanded` and `report-outcome.mjs`'s changed-file and commit reads use it. `report-outcome.mjs` no longer holds a pull request only because its listing reached 300 files. A binary file, a diff that does not parse, or a diff naming fewer files than the pull request changes still carries nothing. `github-client.mjs` `createGitHub` and `retry-fetch.mjs` `retryApi` return the answer's text for a non-JSON media type.
