---
bump: patch
---

### Fixed

- `babysit_review_evidence.bind()` no longer trusts a lane comment someone else edited. Anyone with write access to a repository can edit a comment, so the pull request's own pusher could rewrite the reviewed-head marker, a summary's `critical-findings:` line, or an inline finding's `severity:` line. A marker, a summary or a thread's first comment now binds only while its last editor (GraphQL `editor` and `lastEditedAt`) is its own author, a Bot; any other editor, or edit fields that were not read, unbinds the lane as `comment-edited`. The lane producer's own marker updates still bind. `babysit_merge._lane_evidence` attaches each lane-author comment's edit record, reading GraphQL only for comments whose `updated_at` differs from `created_at`, and `fetch_review_threads` now reads `lastEditedAt` and `editor` on each thread comment.
