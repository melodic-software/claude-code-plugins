---
bump: major
---

### Removed

- The `block_unresolved_pr_merge_enabled` setting is gone ([#18822](https://github.com/melodic-software/claude-code-plugins/issues/18822)). A saved value there is no longer read, so a saved `false` turns the guard back on; set `merge_guard_enabled` instead.

### Changed

- The merge guard is now `hooks/merge-guard.sh`, switched by `merge_guard_enabled` beside `merge_guard_ignored_checks`.
- What makes a pull request ready to merge is decided in one script, `hooks/merge-readiness.sh`, a copy of the same script the source-control pull-request skill runs before it merges. A refusal now points at `/source-control:pull-request merge`.
- Every page of review threads is read: an unresolved thread past the first 100 blocks, where the guard used to let the merge run unchecked.
- A pull request pr-verify judges and has not judged is no longer held for good: 30 minutes after the head's last check finished, with no check still running, the merge runs with a notice that no verdict was read.
