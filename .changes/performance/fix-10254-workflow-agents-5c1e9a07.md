---
bump: patch
---

### Fixed

- `findings.py transcript-counts` now counts the agents the Workflow tool starts, which it never
  read before: a `workflows` block gives the agent count, results and wall time per workflow,
  per-tool calls and wait across workflow agents, and each Bash command repeated across them with
  p50, p95, max and the peak number of overlapping runs. Agents started after the go-faster
  invocation are left out, as direct subagents are, and a session with no workflow agents prints
  the same output as before.
