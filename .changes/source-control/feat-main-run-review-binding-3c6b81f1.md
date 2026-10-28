---
bump: minor
---

### Added

- hold credentialed workflows and workflow privilege gains for a person

  Every workflow whose token can write, that names a secret other than
  GITHUB_TOKEN, or that mints a lane token, and the review workflows
  themselves, is now a `gate` floor path held for a person. A workflow
  change that gains a write scope (or drops a permissions block onto the
  repository default) holds as `permission-widening-review`, and one that
  adds a pull_request_target or workflow_run trigger as
  `privileged-trigger-review`; both are person codes no cost decision
  clears. A secrets reference is also read from the head text, so a
  workflow with no patch is not skipped.
