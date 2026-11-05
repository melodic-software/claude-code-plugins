---
bump: minor
---

### Changed

- Review discipline D4.6 gives each advisory line in a review summary comment a disposition, as a review thread gets one: fixed in this PR when the scope test places it here, otherwise a grounded `VALID (defer)` answered on the summary, or, where the project's own CLAUDE.md or AGENTS.md pauses new issue filing, an entry under `## Follow-ups` in the PR body with its permalink and the changed line that calls it. An advisory still never holds the merge. `/source-control:pull-request monitor` points its summary-reading step at the rule.
