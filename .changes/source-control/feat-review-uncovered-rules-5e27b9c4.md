---
bump: minor
---

### Added

- `/source-control:pull-request review-comments` also returns `lane-summary` rows: a review body or PR comment by `github-actions[bot]` (user id 41898282) whose last non-blank line is a CI review lane's `claude-lane:` footer. It now reads each PR's comments for these; every other bot's review bodies and PR comments stay excluded. `/corrections:codify reviews` reads the lanes' uncovered rules from these rows.
