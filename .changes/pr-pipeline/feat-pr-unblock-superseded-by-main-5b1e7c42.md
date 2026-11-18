---
bump: minor
---

### Added

- `resolve-conflicts-select` checks, after a conflicted merge and before any model turn, whether main already holds the pull request's change (`.github/scripts/pr-unblock/superseded-by-main.mjs`, git alone, no model): every non-merge commit the head adds since its merge base has a patch-id twin among main's commits since it, or the head's whole diff from that merge base has one main commit's patch-id (a squash merge). Such a pull request escalates the new `superseded-by-main` reason, routed `hold` with owner reason `intent`: the human-gated label and a comment saying main already contains the change, with no conflict-resolution run. The lane never closes it. A pull request main holds only part of goes on to the model as before.
