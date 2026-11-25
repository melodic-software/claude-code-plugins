---
bump: minor
---

### Added

- Review criteria compose the organization's `REVIEW.md` (the repository `standards_repository` names, read from its `main`) with the repository's appended; a repository `REVIEW.md` whose first non-blank line is `<!-- review-base: replace -->` replaces it. `scripts/org-standards.sh review` prints the result, and the CI lane reads the composed file a `REVIEW CRITERIA:` line names. Standards contract 1.2.0 adds the org layer beneath the team layer.
