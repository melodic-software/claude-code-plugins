---
bump: minor
---

### Added

- `/source-control:pull-request review-comments --prs <n> [--repo <owner/repo>]` prints the review comments of the last merged pull requests as JSON lines. It keeps the PR author's own comments made after the merge, and never a reply.
