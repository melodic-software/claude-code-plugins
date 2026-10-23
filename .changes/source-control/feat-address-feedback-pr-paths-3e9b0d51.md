---
bump: minor
---

### Changed

- The review-thread tool (`feedback-thread.sh`) of `/source-control:pull-request comments --ci` admits a file in the thread file's `pr_paths`, the files the pull request already changes, in every kept thread's scope while the gated head holds it. `reference/comments-ci.md` tells the model to run `check-paths` before calling a fix out of scope, and to cite a changed line in such a file as evidence.
