---
bump: minor
---

### Changed

- The pr-merge lane no longer lets a pass clear an earlier head's `verify:earlier-fail` when the pull request's own change at the head (the stable patch id of its compare diff from the merge base with the branch) equals its change at a failed head, so a head that only merges the base or adds an empty commit keeps the hold, as does a change that cannot be read. Counted fails at `merge.max-verify-fails` (default 3) distinct heads of one pull request refuse `verify:repeated-fail`, which needs a human, whatever a later pass says; a value that is not a count of 1 or more is 1. The escalation names the refusal, and skip-unchanged carries it forward like the other verifier refusals.
