---
bump: minor
---

### Added

- `block-github-post-content` on the Bash and PowerShell row blocks a `gh pr|issue comment|review|create|edit`, a writing `gh api`, or a curl post to the GitHub API whose body holds a secret pattern or a hardcoded machine-specific path, with the secret-pattern-detection and hardcoded-path-check pattern sets. A secret block names the pattern class, never the value. Escape: `block_github_post_content_enabled`.

### Fixed

- `block-fix-request-post` now reads the command a script wrapper runs after `--` (`bash gate.sh run KEY -- gh ...`, split on bare `+++`), which it passed unread before. Its body parse moved to `lib/github-post/github-post-body.sh`, shared with the new guard.
