---
bump: patch
---

### Fixed

- The work-resolve-issue lane no longer opens a `Refs:` PR for an issue its run delivered whole. `report-outcome` derives the link line from the outcome's `remaining` list and ignores the run's `link` field: a non-empty list opens a `Refs:` PR with a `## Remaining work` section naming each part, which is the remaining work pr-verify's Refs rule asks the body to name. A `remaining` that is not 1 to 20 strings with text counts as empty, so the PR closes the issue.
