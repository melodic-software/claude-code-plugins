---
bump: patch
---

### Changed

- plugin-eval now says a run that ended on an API error, a usage or rate limit included, gets 0
  with no grader run, matching the current plugin-evals page, and no longer counts the exit-1
  causes. Trust, output-location, background-limit and report-publishing notes point at their
  docs sections, and the Sources records carry section anchors. No behavior change.
