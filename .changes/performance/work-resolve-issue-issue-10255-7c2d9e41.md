---
bump: patch
---

### Fixed

- `/performance:go-faster`: the `session-work` and `orchestration` areas now read the `workflows` block of `transcript-counts`, so a session that delegates through the Workflow tool gets findings for it. `session-work` records the slowest tool, any tool with repeated errors, and each Bash command repeated across the Workflow-tool agents. `orchestration` records the longest workflow wall time with the workflow, agent and result counts, or the agent count when no workflow agent has a timestamp. Workflow numbers stay apart from the main session's. A session with a transcript and evidence of work gets `orchestration`'s "no delegation time" `no-data` only when it made no subagent call and started no Workflow-tool agent.
