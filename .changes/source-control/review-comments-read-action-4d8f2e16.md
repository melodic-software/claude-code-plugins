---
bump: minor
---

### Added

- `/source-control:pull-request review-comments --prs <n> [--repo <owner/repo>]` prints the review comments of the last `<n>` pull requests by merge time as JSON lines, widening its read of recently updated merged pull requests until no unread one can be among them. It keeps the PR author's own comments made after the merge, and never a reply.
