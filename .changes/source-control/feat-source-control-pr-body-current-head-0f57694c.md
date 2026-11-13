---
bump: minor
---

### Added

- `/source-control:pull-request`: `pr_body_preview` (`post` by default, or `preview`) prints a PR body and waits for a yes before `create` or a body edit posts it, in attended runs only.
- `/source-control:pull-request`: `pr_body_refresh` (on by default). A push to an open PR that makes its body stale (what changed, verification, `Left out:`) now rewrites those sections in place with `gh pr edit --body-file`, never with a comment, so the body describes the current head.

### Changed

- The `briefing` preset's `Risk` section says what the change reaches and how it is undone, and states no door or risk tier; `/review:merge-risk` keeps the rating.
- A review-fix round, attended or `comments --ci`, fixes every instance of a finding's class in the diff, not only the flagged line.
