---
bump: minor
---

### Added

- A comment lint, the git-hook entry `comment-lint`: it judges the comment lines a change adds
  against the comment posture and names the fix for each one outside it. The team setting
  `comment_lint` sets its level (`off` by default, `report`, `block`) and `comment_lint_allow` adds
  patterns for a repository's own markers. `/code-tidying:setup apply install-git-hooks` installs
  it; it needs Python 3 with pygments.
- `/code-tidying:remove-comments --base <ref>`: the scope is the branch's changed code files
  against the merge base, at the granularity `comment_edit_scope` sets, and it never widens to the
  repository.
- The comment trailing a `uses:` line pinned to a full commit id is kept in every posture.

### Changed

- `/code-tidying:tidy` reads `comment_posture`: under `necessary` it adds only a comment the keep
  list keeps, under `none` it adds none, and `explanatory` is unchanged.
