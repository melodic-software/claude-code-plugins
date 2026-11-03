---
bump: patch
---

### Changed

- `/planning:design`, `/planning:plan`, `/planning:prd`, `/planning:interview` and
  `/planning:draft-goal-condition` no longer restate upstream behavior (how injected commands run,
  Mermaid's C4 support, plan mode, the `/plan` command, the `Plan` subagent, the `/goal`
  evaluator, limit and permissions). Each keeps its own rule and links the upstream section with
  an as-of date and a recheck trigger.
