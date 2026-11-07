---
bump: patch
---

### Changed

- `reference/standing-item-preconditions.md`: an agent settles the `frontier-release-since-last-checked` precondition by reading the official release notes page the row's `prompt` names. With no release since `last_checked`, it runs nothing and recheck-closes the item, setting `last_checked` to the read date and advancing `next_due`. With a release, it runs the pass. Only an unreadable page leaves the item open.
- `scripts/evaluate-schedule-precondition.sh` prints the row's `prompt` ahead of `met` when the precondition has no operator gate. A `work` or `recheck` caller then gets the steps it must settle, instead of a bare `met` that reads as already checked.
