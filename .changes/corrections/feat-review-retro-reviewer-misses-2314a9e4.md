---
bump: minor
---

### Changed

- Codify's `automated-review` rung writes to the repository's review-criteria index when it has
  one, else a repository-owned `CODING_STANDARDS.md`, else `REVIEW.md`, and skips a file a
  standards-sync bot owns (enforcement-ladder 3.4.0).
