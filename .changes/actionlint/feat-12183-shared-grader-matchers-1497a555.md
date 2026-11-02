---
bump: patch
---

### Changed

- The check and setup eval cases build their command-position and status-table graders from the evals plugin's shared matchers, with no change to any pattern. `routes-to-setup-apply`, `names-setup-apply` and `no-successor` judge the reply's route with an `llm` grader instead of a regex.
