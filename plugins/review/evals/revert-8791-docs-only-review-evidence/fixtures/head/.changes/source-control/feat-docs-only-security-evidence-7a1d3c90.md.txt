---
bump: minor
---

### Added

- count the security lane's docs-only skip as its review of an all-docs pull request

  The merge gate read `skip=docs-only` from the security review lane as no
  review, so a documentation-only pull request never merged unattended. That
  skip now binds the security lane, with no findings of its own, when every
  path the pull request changes matches the lane's docs-only default
  (`docs/**/*.md`, `**/README.md`, `**/CHANGELOG.md`) and none is an agent
  instruction path. Open security threads still count, and the code review
  lane still needs a review.
