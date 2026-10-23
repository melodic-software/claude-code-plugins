---
bump: minor
---

### Changed

- The merge gate's review evidence accepts the security lane on ci-workflows' `pr-review-cli.yml`: a completion record ending in `account=fallback`, and a `github-actions[bot]` thread or summary comment whose last non-blank line is the lane's `claude-lane:` footer. A reviewed-head marker is never read a second time as a summary comment.
