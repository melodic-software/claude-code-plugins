---
bump: patch
---

### Fixed

- A pr-verify fail on a pull request a person opened no longer holds it with review threads the lanes App cannot resolve (GitHub lets only the author or a writer resolve one, and every conversation must be resolved to merge). `verify-notes.mjs` now posts the fail as one pull request comment, edited in place on a later fail, and adds the `pr-verify-failed` label; a pass at the pull request's head removes the label. ci-status's merge-queue run fails while the label is on, as it does for `do-not-merge`. `feedback-dispatch.mjs` no longer sends a pass-only round to such a pull request. Lanes App pull requests keep their fail-note threads and pass-only round.
