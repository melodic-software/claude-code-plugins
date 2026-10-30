---
bump: patch
---

### Changed

- The `pre-commit-content` git hook reads and scans the staged files in batches, so a commit of many files, such as a merge of the default branch, no longer starts several processes for each file ([#10591](https://github.com/melodic-software/claude-code-plugins/issues/10591)). It reads each staged file once, finds the files a secret pattern can match with one search over all of them, and checks the files that may hold a machine path together, then one by one only where that check finds something. It still reads every line it read before and reports the same findings. A staged file the hook cannot read out, or cannot write to its temporary directory, now blocks the commit with a message instead of going unscanned.
