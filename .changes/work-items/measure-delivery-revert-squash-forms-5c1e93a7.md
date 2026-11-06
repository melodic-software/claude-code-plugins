---
bump: patch
---

### Fixed

- measure-delivery: count `revert:` and `revert(<scope>):` squash commits as reverts

  A commit with a revert subject now reverts the deployment its
  `Reverts [<owner>/<repo>]#<n>` body line or `(#<n>` subject group names
  by pull request number, else the one its quoted or remaining subject
  matches; `This reverts commit <sha>` still comes first. A revert subject
  that names no deployment counts as rework and in the new
  `unresolved_reverts` count, never dropped. Targets that landed before
  `--since` now resolve.
