---
bump: patch
---

### Changed

- `pull-request` B2 states when a push needs a fresh AI review round: only when it changed reviewed content, and any conflict resolution in code counts. A push that only merged the default branch needs none when `git show --remerge-diff` of the merge is fully empty, with no paths excluded; an empty result does not detect semantic interaction with what the base brought in. The monitor applies the same test before waiting on lanes, and B2 applies unchanged when the test cannot be computed ([#6632](https://github.com/melodic-software/claude-code-plugins/issues/6632)).
