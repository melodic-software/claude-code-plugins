---
bump: minor
---

### Added

- work-item tracker: add feature-detected GitHub Issue Artifacts (`put-artifact`, `list-artifacts`, `get-artifact`) and symmetric `"Relates to"` (`link-relates`, `unlink-relates`, `list-relates`) verbs with graceful exit `6` fallback when unavailable, plus concise artifact/link guidance in `publish-plan`, `edit`, `work`, and `decompose` (Refs #19449).
