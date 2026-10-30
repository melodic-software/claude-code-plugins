---
bump: minor
---

### Added

- The monitoring lane has signal 11, post-merge unreadable: when the newest 4 post-merge reports that `pr-merge`'s `post-merge-dispatch` kept all exited 3 (the check could not read lane merges, so merges hold with only a warning), it files or reopens one rolling issue naming the newest report's reason, and each monitoring run prints it as an `::error` while it holds. It only notifies, and the next readable report closes it. No report within 70 minutes leaves the signal unread rather than clearing it.
