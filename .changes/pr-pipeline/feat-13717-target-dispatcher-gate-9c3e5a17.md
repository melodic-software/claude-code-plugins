---
bump: minor
---

### Added

- The trusted-trigger gate accepts a `pull_request_target` run of the unblock dispatcher that vouches for one `pr-refine.yml` run, proven by the pull request entry and a record naming the `main` commit it ran (ADR 0090). No workflow carries the trigger yet.
