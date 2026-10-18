---
bump: patch
---

### Changed

- `pull-request` B2 states when a push needs a fresh AI review round: only when it changed reviewed content, and any conflict resolution in code counts. A merge of the default branch needs none when `git show --remerge-diff`, limited to paths outside CHANGELOG files, `plugin.json` version lines and `.changes/` fragments, is empty. The monitor applies the same test before waiting on lanes, and B2 applies unchanged when the test cannot be computed ([#6632](https://github.com/melodic-software/claude-code-plugins/issues/6632)).
