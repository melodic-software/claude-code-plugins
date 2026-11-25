---
bump: minor
---

### Added

- Standards resolution reads personal subscriptions, standards contract 1.3.0: the repositories the user-global index lists in `standards_repositories`, each a personal layer beneath the user's own standards files and every team-tracked one. `scripts/org-standards.sh subscriptions` prints each layer with its checkout and its topic-filtered index; an untrusted owner's repository must be pinned to a commit one of its branches or tags reaches.

### Fixed

- `scripts/org-standards.sh` confines the org layer and every subscribed layer to its own checkout: a `standards_dir` or index `File` value that is absolute, has a `..` segment or resolves through a symbolic link outside the checkout is reported and dropped, and so is an org `REVIEW.md` that resolves outside it. Its clones, fetches and `ls-remote` calls give up after `ORG_STANDARDS_GIT_TIMEOUT` seconds (default 60), never prompt, and use no credential helper.
