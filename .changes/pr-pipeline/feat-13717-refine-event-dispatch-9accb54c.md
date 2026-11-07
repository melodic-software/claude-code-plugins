---
bump: minor
---

### Added

- The pr-run-activity convention describes the `refine` job of `pr-unblock-dispatch.yml`, which
  starts fix-docs on a pull request's own `pull_request_target` event under the push dispatcher's
  once-per-PR rule and records the dispatch for the trusted-trigger gate.
