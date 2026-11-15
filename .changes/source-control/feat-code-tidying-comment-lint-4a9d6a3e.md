---
bump: minor
---

### Changed

- Pull-request prep runs the comment pass as `/code-tidying:remove-comments --pipeline --base
  <remote>/<base-branch>`, so the repository's `comment_edit_scope` decides whether it triages the
  added lines or each changed file whole. A repository that leaves the setting at `diff` sees no
  change.
