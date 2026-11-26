---
bump: minor
---

### Added

- The bundled standards contract is at 1.3.0, which adds personal subscriptions: the repositories the user-global index lists in `standards_repositories`, each a personal layer beneath the user's own standards files and every team-tracked one. `scripts/org-standards.sh subscriptions` prints each layer with its checkout and its topic-filtered index, reading the list with the newly bundled `lib/yaml-subset.awk`.

### Fixed

- `scripts/org-standards.sh` confines the org layer and every subscribed layer to its own checkout: a `standards_dir` or index `File` value that is absolute, has a `..` segment or resolves through a symbolic link outside the checkout is reported and dropped, and so are an org `REVIEW.md` or `.claude/standards.yaml` that resolves outside it and an org `REVIEW.md` line whose `<path>.md#<heading>` citation does. `index` and `subscriptions` print a copy of each index written under the reader's cache state, never inside a checkout, keeping only well-formed table rows, each `File` rewritten to the absolute path it resolves to inside the checkout. Its clones, fetches, `ls-remote` calls and lazy object fetches give up after `ORG_STANDARDS_GIT_TIMEOUT` seconds (default 60), never prompt, and use no credential helper.
