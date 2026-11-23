---
bump: patch
---

### Changed

- `/source-control:pull-request merge` now says that where the guardrails `block-unresolved-pr-merge` hook is enabled, a head pr-verify has not passed stays held after the 30-minute verdict wait instead of merging with no verdict read.
