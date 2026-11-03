---
bump: patch
---

### Changed

- The `find` CI-health context no longer states the REST `per_page` cap, what `run_attempt`,
  `run_started_at` and `created_at` mean, or which filters and options the GitHub MCP tools lack.
  It keeps the window and paging rules, the three fields per run and the MCP-path rule, and
  points at the workflow-runs REST sections and the GitHub MCP Server tools list.
