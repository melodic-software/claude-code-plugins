---
bump: minor
---

### Changed

- `/harness-config:audit-instructions` checks Claude Fable 5.2 and Claude Mythos 5.2 requests: I17's outright-disable arm, I17-c's fixed-budget set and I25's sampling-parameter set now name both models, each on the thinking pages' per-model lists. I20 keeps its release-floor range, which already reaches Fable 5.2, and records the re-read.

### Fixed

- I8-c's `Model scope` header no longer lists `sonnet-5-5`, matching the row's declined Sonnet 5.5 widening, so the row stays inert on a Sonnet 5.5 target.
