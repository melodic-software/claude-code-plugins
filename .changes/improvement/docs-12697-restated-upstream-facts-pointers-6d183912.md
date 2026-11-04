---
bump: patch
---

### Changed

- The `find` CI-health context no longer states the REST `per_page` cap, what `run_attempt` and
  the latest attempt's duration record, or the `get_job_logs` failed-jobs option. It keeps the
  window and paging rules with their reasons, the three fields per run, why `created_at` is not
  used, and why the MCP path cannot window by date, and points at the workflow-runs REST sections
  and the GitHub MCP Server tools list.
