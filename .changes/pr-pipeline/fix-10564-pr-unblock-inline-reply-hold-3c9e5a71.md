---
bump: patch
---

### Fixed

- `resolve-conflicts`, `fix-ci` and `fix-docs` no longer work past another lane's escalation after a person replies inside an existing review thread. GitHub's timeline shows no event for such a reply, so the gate (`gate-source.mjs` `prHold`) now also reads the PR's review comments and reviews, and holds the PR when either read fails.
