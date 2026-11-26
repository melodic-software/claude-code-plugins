---
bump: patch
---

### Fixed

- `pr-merge.yml`'s `wake-eval-released` job reads each released pull request before it dispatches, as `pr-verify.yml`'s `wake-pr-merge` does: one not opened by the lanes App, already armed, or held by `do-not-merge` is not woken and spends none of the five wakes, so a person's held pull request no longer starts a pr-merge run the token broker refuses as `untrusted-author`. A failed read, or no lanes App id, dispatches as before. The job gains `pull-requests: read`.
- A pr-verify `pass` or `pass-notes` on a person's pull request at its head now edits the `<!-- pr-verify:fail-note -->` PR comment an earlier fail left to say it is superseded, naming the passing head (`verify-notes.mjs` `supersededComment`). The marker stays its first line, so a later fail updates the same comment in place; a pull request with no PR comment is not read.
