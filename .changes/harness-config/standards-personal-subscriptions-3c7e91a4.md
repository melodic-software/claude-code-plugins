---
bump: minor
---

### Added

- `audit-automation-gaps`' rule inventory names each personal standards subscription (`scripts/org-standards.sh subscriptions`, standards contract 1.3.0) as present, not counted: it is the user's, not the repository's.

### Fixed

- `scripts/org-standards.sh` confines the org layer and every subscribed layer to its own checkout: a `standards_dir` or index `File` value that is absolute, has a `..` segment or resolves through a symbolic link outside the checkout is reported and dropped, and so is an org `REVIEW.md` that resolves outside it. Its clones, fetches and `ls-remote` calls give up after `ORG_STANDARDS_GIT_TIMEOUT` seconds (default 60), never prompt, and use no credential helper.
