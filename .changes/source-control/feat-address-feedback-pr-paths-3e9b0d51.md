---
bump: minor
---

### Changed

- The review-thread tool (`feedback-thread.sh`) of `/source-control:pull-request comments --ci` admits a file in the thread file's `pr_paths`, the files the pull request already changes, in every kept thread's scope while the gated head holds it. An instruction path and the trusted-actor list, trusted-trigger check and `resolve-config` stay refused. `reference/comments-ci.md` says so.
