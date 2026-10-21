---
bump: minor
---

### Changed

- The pr-merge lane no longer holds a pull request for an earlier head's `verify:earlier-fail` once its current head has counted pass or pass-notes verdicts whose runs were all created after every such fail's run (each `created_at` read fresh from GitHub, which a re-attempt keeps), and the pull request's own change at the head differs from its change at every failed head. That change is a digest of the changed lines in the compare diff from the merge base with the base branch, so a head that only merges the base, an empty commit, or a whitespace-only edit keeps the hold, as does a diff that cannot be read. Those passes then decide, so a changed or untrusted spec still refuses. Skip-unchanged no longer carries a `verify:earlier-fail` forward while a pass artifact names the head.

### Added

- `merge.max-verify-fails` (default 3): counted fails at that many distinct heads refuse `verify:repeated-fail`, which needs a human, whatever a later pass says. Fails of other open or closed pull requests in the repository that close the same issue count too, so a new pull request does not reset the count. A value that is not a count of 1 or more, empty or non-scalar included, is 1. The escalation comment names the refusal, and skip-unchanged carries it forward like the other verifier refusals.

### Fixed

- A run record whose id is a boolean no longer stands for run 1.
